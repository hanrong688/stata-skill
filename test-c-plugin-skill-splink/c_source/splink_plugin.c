/*
 * splink_plugin.c — Probabilistic record linkage for Stata
 *
 * Full-fidelity implementation of the Fellegi-Sunter model matching
 * the Python splink package's core capabilities:
 *   - Configurable comparison levels per field (variable number)
 *   - Multiple comparison functions (JW, Jaro, Levenshtein, DL, Jaccard, exact)
 *   - Term frequency adjustments
 *   - Multiple blocking rules with OR logic + pair deduplication
 *   - Null level (neutral weight, not penalizing)
 *   - Configurable prior match probability
 *   - link_and_dedupe mode
 *   - Pairwise output (match_weight, match_probability per pair)
 *   - User-fixable m/u probabilities
 *
 * Configuration is passed via a tempfile (INI-style) written by the .ado wrapper.
 *
 * Variable layout (from .ado):
 *   Vars 1..n_block_rules:                   block keys (strings, one per rule)
 *   Vars n_block_rules+1..n_block_rules+n_comp: comparison variables
 *   [Var n_block_rules+n_comp+1]:            link_source (if linking)
 *   Last var:                                cluster_id (OUTPUT)
 *
 * Arguments:
 *   argv[0] = path to config file
 *   argv[1] = path to diagnostics output file
 *
 * License: MIT
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <stdint.h>
#include <ctype.h>
#include <stdarg.h>
#include <limits.h>

#include "stplugin.h"

/* ========================================================================
 * Constants
 * ======================================================================== */

#define MAX_STR_LEN        245   /* str244 + null terminator */
#define MAX_COMP_VARS      20    /* max comparison variables */
#define MAX_LEVELS         10    /* max comparison levels per field */
#define MAX_BLOCK_RULES    32    /* max OR-combined blocking rules (raised from 4) */
#define MAX_THRESHOLDS     8     /* max thresholds per comparison */
#define EM_TOL             1e-5  /* EM convergence threshold */
#define MAX_LINE           1024  /* config file line buffer */
#define TF_HASH_SIZE       8192  /* term frequency hash table buckets */
#define MAX_INPUT_VARS     4     /* max input vars per multi-column comparison */
#define MAX_VAR_NAME       64    /* max variable name length */
#define EM_MAX_HISTORY     200   /* max EM iterations to record */

/* Static EM iteration history (single-threaded Stata plugin, safe as static) */
static int    em_hist_n = 0;
static double em_hist_lambda[EM_MAX_HISTORY];
static double em_hist_maxchange[EM_MAX_HISTORY];

/* Comparison methods */
#define METHOD_JW          0     /* Jaro-Winkler similarity */
#define METHOD_JARO        1     /* Jaro similarity */
#define METHOD_LEV         2     /* Levenshtein distance */
#define METHOD_DL          3     /* Damerau-Levenshtein distance */
#define METHOD_JACCARD     4     /* Jaccard similarity on bigrams */
#define METHOD_EXACT       5     /* Binary exact match */
#define METHOD_NUMERIC     6     /* Numeric absolute difference */
/* Domain-specific comparison methods */
#define METHOD_DOB         7     /* Date of birth comparison */
#define METHOD_EMAIL       8     /* Email address comparison */
#define METHOD_POSTCODE    9     /* Postcode/zipcode comparison */
#define METHOD_NAMESWAP   10     /* Name swap (forename/surname) */
#define METHOD_NAME       11     /* Name with phonetic check */
#define METHOD_ABS_DATE   12     /* Absolute date difference */
#define METHOD_DISTANCE   13     /* Haversine distance (lat/lon) */
#define METHOD_COSINE     14     /* Cosine similarity (string bigrams) */
#define METHOD_CUSTOM     15     /* User-precomputed gamma */
#define METHOD_PCT_DIFF   16     /* Percentage difference (numeric) */
#define METHOD_INTERSECT  17     /* Token intersection size (strings) */
#define METHOD_ABS_TIME   18     /* Absolute time difference (Stata %tc = ms) */

/* Link types */
#define LINK_DEDUPE        0
#define LINK_ONLY          1
#define LINK_AND_DEDUPE    2

/* Null handling */
#define NULL_NEUTRAL       0     /* null -> Bayes factor = 1 (no contribution) */
#define NULL_PENALIZE      1     /* null -> level 0 (else) */

/* Plugin modes */
#define MODE_LEGACY        0     /* Single command (backward compatible) */
#define MODE_TRAIN         1     /* Training: estimate u, then EM for m */
#define MODE_SCORE         2     /* Score using pre-loaded parameters */
#define MODE_GAMMA         3     /* Gamma-only: output comparison vectors, no EM */

/* ========================================================================
 * Configuration Structure
 * ======================================================================== */

typedef struct {
    /* Per-comparison-variable settings */
    int    method;                      /* METHOD_JW, METHOD_LEV, etc. */
    int    is_string;                   /* 1 for string, 0 for numeric */
    int    n_levels;                    /* else + thresholds + exact (null=-1, not in array) */
    double thresholds[MAX_THRESHOLDS];  /* comparison thresholds */
    int    n_thresholds;                /* number of user thresholds */
    int    tf_adjust;                   /* 1 if TF adjustment enabled */
    double tf_min;                      /* minimum TF u-value */
    char   tf_file[512];               /* path to TF table file */
    int    fix_m;                       /* 1 if m probs are fixed */
    int    fix_u;                       /* 1 if u probs are fixed */
    double fixed_m[MAX_LEVELS];         /* fixed m values */
    double fixed_u[MAX_LEVELS];         /* fixed u values */
    /* V2 extensions */
    int    n_input_vars;                /* number of input vars (1=single, 2-4=multi-column) */
    int    input_var_indices[MAX_INPUT_VARS]; /* indices into allvars array */
    char   var_name[MAX_VAR_NAME];      /* variable name for named output columns */
    int    null_mode;                   /* per-variable null override (-1=use global) */
    /* V3 extensions — feature parity with Python splink v4 */
    double tf_weight;                   /* TF blending weight 0-1 (default 1.0 = full TF) */
    int    tf_exact_only;               /* 1 = apply TF only to exact-match level (Python default) */
    int    fix_m_mask;                  /* bitmask: bit l set = level l m-prob is fixed (0=use fix_m) */
    int    fix_u_mask;                  /* bitmask: bit l set = level l u-prob is fixed (0=use fix_u) */
    double time_unit_divisor;           /* for METHOD_ABS_TIME: ms divisor */
} CompConfig;

typedef struct {
    int        n_comp;
    int        n_block_rules;
    int        link_type;               /* LINK_DEDUPE, LINK_ONLY, LINK_AND_DEDUPE */
    int        null_weight;             /* NULL_NEUTRAL or NULL_PENALIZE */
    double     threshold;
    double     prior;
    int        max_iter;
    int        max_block_size;          /* 0 = no limit */
    int        verbose;
    int        estimate_u;              /* 1 = estimate u via random sampling */
    int        u_max_pairs;             /* max random pairs for u estimation */
    int        u_seed;                  /* seed for random u estimation */
    char       save_pairs[512];         /* path for pairwise output, empty=none */
    CompConfig comp[MAX_COMP_VARS];
    /* V2 extensions */
    int        mode;                    /* MODE_LEGACY, MODE_TRAIN, MODE_SCORE */
    int        config_version;          /* 1 = legacy INI, 2 = V2 format */
    int        n_allvars;               /* total unique vars (blocking + comparison) */
    char       id_var_name[MAX_VAR_NAME]; /* user ID variable name for output */
    int        has_id_var;              /* 1 if id variable is passed */
    /* V3 extensions — feature parity with Python splink v4 */
    double     recall;                  /* recall adjustment for lambda estimation (default 1.0) */
    int        fix_lambda;              /* 1 = don't update lambda during EM */
    int        em_without_tf;           /* 1 = skip TF adjustments during EM */
    double     cluster_threshold;       /* separate threshold for clustering (default = threshold) */
    int        use_weight_threshold;    /* 1 = threshold on match_weight instead of probability */
    double     weight_threshold;        /* match_weight threshold (log2 BF) */
    int        cluster_method;          /* 0=connected-components, 1=best-link */
    int        salt_partitions;         /* blocking salting: 0=disabled, N>0 = partition count */
    int        round_robin_em;          /* 1 = EM per blocking rule, then average */
    double     em_tol;                  /* EM convergence tolerance (default 1e-5) */
} Config;

/* ========================================================================
 * Term Frequency Hash Table
 * ======================================================================== */

typedef struct TFEntry {
    char   *key;
    double  freq;
    struct TFEntry *next;
} TFEntry;

typedef struct {
    TFEntry *buckets[TF_HASH_SIZE];
    int      n_entries;
} TFTable;

static unsigned int tf_hash(const char *s) {
    unsigned int h = 5381;
    while (*s) h = ((h << 5) + h) + (unsigned char)*s++;
    return h % TF_HASH_SIZE;
}

static TFTable *tf_create(void) {
    TFTable *t = calloc(1, sizeof(TFTable));
    return t;
}

static void tf_insert(TFTable *t, const char *key, double freq) {
    if (!t) return;
    unsigned int h = tf_hash(key);
    TFEntry *e = malloc(sizeof(TFEntry));
    if (!e) return;
    e->key = malloc(strlen(key) + 1);
    if (!e->key) { free(e); return; }
    strcpy(e->key, key);
    e->freq = freq;
    e->next = t->buckets[h];
    t->buckets[h] = e;
    t->n_entries++;
}

static double tf_lookup(TFTable *t, const char *key, double default_val) {
    if (!t) return default_val;
    unsigned int h = tf_hash(key);
    for (TFEntry *e = t->buckets[h]; e; e = e->next) {
        if (strcmp(e->key, key) == 0) return e->freq;
    }
    return default_val;
}

static void tf_free(TFTable *t) {
    if (!t) return;
    for (int i = 0; i < TF_HASH_SIZE; i++) {
        TFEntry *e = t->buckets[i];
        while (e) {
            TFEntry *next = e->next;
            free(e->key);
            free(e);
            e = next;
        }
    }
    free(t);
}

static TFTable *tf_load_file(const char *path) {
    FILE *f = fopen(path, "r");
    if (!f) return NULL;
    TFTable *t = tf_create();
    if (!t) { fclose(f); return NULL; }

    char line[MAX_LINE];
    /* skip header */
    if (!fgets(line, sizeof(line), f)) { fclose(f); tf_free(t); return NULL; }

    while (fgets(line, sizeof(line), f)) {
        /* format: value,frequency (RFC 4180: quoted values may contain commas) */
        char *p = line;
        char *comma;
        if (*p == '"') {
            /* Quoted field — find closing quote (skip escaped "") */
            p++;
            char *end = p;
            while (*end) {
                if (*end == '"' && *(end + 1) == '"') { end += 2; continue; }
                if (*end == '"') break;
                end++;
            }
            /* Extract unquoted value */
            *end = '\0';
            comma = strchr(end + 1, ',');
        } else {
            comma = strchr(line, ',');
        }
        if (!comma) continue;
        *comma = '\0';
        double freq = atof(comma + 1);
        /* trim newline */
        char *nl = strchr(comma + 1, '\n');
        if (nl) *nl = '\0';
        tf_insert(t, p, freq);
    }
    fclose(f);
    return t;
}

/* ========================================================================
 * Utility Functions
 * ======================================================================== */

static void str_tolower(char *s) {
    for (; *s; s++) *s = (char)tolower((unsigned char)*s);
}

static void str_trim(char *s) {
    int len = (int)strlen(s);
    while (len > 0 && isspace((unsigned char)s[len - 1]))
        s[--len] = '\0';
    char *start = s;
    while (*start && isspace((unsigned char)*start)) start++;
    if (start != s) memmove(s, start, strlen(start) + 1);
}

static char *str_strip(char *s) {
    while (*s && isspace((unsigned char)*s)) s++;
    char *end = s + strlen(s) - 1;
    while (end > s && isspace((unsigned char)*end)) *end-- = '\0';
    return s;
}

/* Write a string field to a CSV file with RFC 4180 escaping.
 * If the field contains comma, double-quote, or newline, wrap in quotes
 * and double any internal quotes. */
static void csv_write_field(FILE *f, const char *s) {
    int needs_quote = 0;
    for (const char *p = s; *p; p++) {
        if (*p == ',' || *p == '"' || *p == '\n' || *p == '\r') {
            needs_quote = 1;
            break;
        }
    }
    if (!needs_quote) {
        fputs(s, f);
    } else {
        fputc('"', f);
        for (const char *p = s; *p; p++) {
            if (*p == '"') fputc('"', f);
            fputc(*p, f);
        }
        fputc('"', f);
    }
}

/* ========================================================================
 * String Comparison Functions
 * ======================================================================== */

/* --- Jaro Similarity --- */

static double jaro_similarity(const char *s1, const char *s2) {
    int len1 = (int)strlen(s1);
    int len2 = (int)strlen(s2);

    if (len1 == 0 && len2 == 0) return 1.0;
    if (len1 == 0 || len2 == 0) return 0.0;

    int match_dist = (len1 > len2 ? len1 : len2) / 2 - 1;
    if (match_dist < 0) match_dist = 0;

    int stack1[512], stack2[512];
    int *s1_matched, *s2_matched;
    int on_heap = 0;

    if (len1 <= 512 && len2 <= 512) {
        s1_matched = stack1;
        s2_matched = stack2;
        memset(s1_matched, 0, (size_t)len1 * sizeof(int));
        memset(s2_matched, 0, (size_t)len2 * sizeof(int));
    } else {
        s1_matched = calloc((size_t)len1, sizeof(int));
        s2_matched = calloc((size_t)len2, sizeof(int));
        on_heap = 1;
        if (!s1_matched || !s2_matched) {
            if (s1_matched) free(s1_matched);
            if (s2_matched) free(s2_matched);
            return 0.0;
        }
    }

    int matches = 0;
    for (int i = 0; i < len1; i++) {
        int lo = i - match_dist;
        int hi = i + match_dist + 1;
        if (lo < 0) lo = 0;
        if (hi > len2) hi = len2;
        for (int j = lo; j < hi; j++) {
            if (s2_matched[j] || s1[i] != s2[j]) continue;
            s1_matched[i] = 1;
            s2_matched[j] = 1;
            matches++;
            break;
        }
    }

    if (matches == 0) {
        if (on_heap) { free(s1_matched); free(s2_matched); }
        return 0.0;
    }

    int transpositions = 0;
    int k = 0;
    for (int i = 0; i < len1; i++) {
        if (!s1_matched[i]) continue;
        while (!s2_matched[k]) k++;
        if (s1[i] != s2[k]) transpositions++;
        k++;
    }

    if (on_heap) { free(s1_matched); free(s2_matched); }

    double m = (double)matches;
    return (m / len1 + m / len2 + (m - transpositions / 2.0) / m) / 3.0;
}

/* --- Jaro-Winkler Similarity --- */

static double jaro_winkler_similarity(const char *s1, const char *s2) {
    double jaro = jaro_similarity(s1, s2);

    int prefix = 0;
    int max_prefix = 4;
    int min_len = (int)strlen(s1);
    int l2 = (int)strlen(s2);
    if (l2 < min_len) min_len = l2;
    if (max_prefix > min_len) max_prefix = min_len;

    for (int i = 0; i < max_prefix; i++) {
        if (s1[i] == s2[i]) prefix++;
        else break;
    }

    return jaro + prefix * 0.1 * (1.0 - jaro);
}

/* --- Levenshtein Distance (Wagner-Fischer, 2-row space optimization) --- */

static int levenshtein_distance(const char *s1, const char *s2) {
    int len1 = (int)strlen(s1);
    int len2 = (int)strlen(s2);

    if (len1 == 0) return len2;
    if (len2 == 0) return len1;

    /* Ensure len1 <= len2 for space optimization */
    if (len1 > len2) {
        const char *tmp = s1; s1 = s2; s2 = tmp;
        int t = len1; len1 = len2; len2 = t;
    }

    int stack_prev[512], stack_curr[512];
    int *prev, *curr;
    int on_heap = 0;

    if (len1 + 1 <= 512) {
        prev = stack_prev;
        curr = stack_curr;
    } else {
        prev = malloc((size_t)(len1 + 1) * sizeof(int));
        curr = malloc((size_t)(len1 + 1) * sizeof(int));
        on_heap = 1;
        if (!prev || !curr) {
            if (prev) free(prev);
            if (curr) free(curr);
            return len2; /* fallback */
        }
    }

    for (int j = 0; j <= len1; j++) prev[j] = j;

    for (int i = 1; i <= len2; i++) {
        curr[0] = i;
        for (int j = 1; j <= len1; j++) {
            int cost = (s1[j-1] == s2[i-1]) ? 0 : 1;
            int ins = curr[j-1] + 1;
            int del = prev[j] + 1;
            int sub = prev[j-1] + cost;
            curr[j] = ins < del ? (ins < sub ? ins : sub) : (del < sub ? del : sub);
        }
        int *tmp = prev; prev = curr; curr = tmp;
    }

    int result = prev[len1];
    if (on_heap) { free(prev); free(curr); }
    return result;
}

/* --- Damerau-Levenshtein Distance (Optimal String Alignment variant) --- */

static int damerau_levenshtein_distance(const char *s1, const char *s2) {
    int len1 = (int)strlen(s1);
    int len2 = (int)strlen(s2);

    if (len1 == 0) return len2;
    if (len2 == 0) return len1;

    /* Need 3 rows for transposition check */
    int *row0, *row1, *row2;
    int on_heap = 0;
    int stack0[512], stack1[512], stack2[512];

    if (len2 + 1 <= 512) {
        row0 = stack0; row1 = stack1; row2 = stack2;
    } else {
        row0 = malloc((size_t)(len2 + 1) * sizeof(int));
        row1 = malloc((size_t)(len2 + 1) * sizeof(int));
        row2 = malloc((size_t)(len2 + 1) * sizeof(int));
        on_heap = 1;
        if (!row0 || !row1 || !row2) {
            if (row0) free(row0);
            if (row1) free(row1);
            if (row2) free(row2);
            return len1 > len2 ? len1 : len2;
        }
    }

    for (int j = 0; j <= len2; j++) row1[j] = j;

    for (int i = 1; i <= len1; i++) {
        row2[0] = i;
        for (int j = 1; j <= len2; j++) {
            int cost = (s1[i-1] == s2[j-1]) ? 0 : 1;
            int ins = row2[j-1] + 1;
            int del = row1[j] + 1;
            int sub = row1[j-1] + cost;
            int best = ins < del ? (ins < sub ? ins : sub) : (del < sub ? del : sub);

            /* Transposition check */
            if (i > 1 && j > 1 &&
                s1[i-1] == s2[j-2] && s1[i-2] == s2[j-1]) {
                int trans = row0[j-2] + cost;
                if (trans < best) best = trans;
            }
            row2[j] = best;
        }
        int *tmp = row0; row0 = row1; row1 = row2; row2 = tmp;
    }

    int result = row1[len2];
    if (on_heap) { free(row0); free(row1); free(row2); }
    return result;
}

/* --- Jaccard Similarity on character bigrams --- */

typedef struct { char a; char b; } Bigram;

static double jaccard_similarity(const char *s1, const char *s2) {
    int len1 = (int)strlen(s1);
    int len2 = (int)strlen(s2);

    if (len1 == 0 && len2 == 0) return 1.0;
    if (len1 < 2 && len2 < 2) return (len1 == len2 && (len1 == 0 || s1[0] == s2[0])) ? 1.0 : 0.0;
    if (len1 < 2 || len2 < 2) return 0.0;

    int nb1 = len1 - 1;
    int nb2 = len2 - 1;

    /* Extract bigrams */
    Bigram stack_bg1[512], stack_bg2[512];
    Bigram *bg1, *bg2;
    int on_heap = 0;

    if (nb1 <= 512 && nb2 <= 512) {
        bg1 = stack_bg1; bg2 = stack_bg2;
    } else {
        bg1 = malloc((size_t)nb1 * sizeof(Bigram));
        bg2 = malloc((size_t)nb2 * sizeof(Bigram));
        on_heap = 1;
        if (!bg1 || !bg2) {
            if (bg1) free(bg1);
            if (bg2) free(bg2);
            return 0.0;
        }
    }

    for (int i = 0; i < nb1; i++) { bg1[i].a = s1[i]; bg1[i].b = s1[i+1]; }
    for (int i = 0; i < nb2; i++) { bg2[i].a = s2[i]; bg2[i].b = s2[i+1]; }

    /* Count intersection (each bigram matched at most once) */
    int stack_used[512];
    int *used;
    int used_heap = 0;
    if (nb2 <= 512) {
        used = stack_used;
    } else {
        used = calloc((size_t)nb2, sizeof(int));
        used_heap = 1;
        if (!used) {
            if (on_heap) { free(bg1); free(bg2); }
            return 0.0;
        }
    }
    memset(used, 0, (size_t)nb2 * sizeof(int));

    int intersection = 0;
    for (int i = 0; i < nb1; i++) {
        for (int j = 0; j < nb2; j++) {
            if (!used[j] && bg1[i].a == bg2[j].a && bg1[i].b == bg2[j].b) {
                intersection++;
                used[j] = 1;
                break;
            }
        }
    }

    int union_size = nb1 + nb2 - intersection;
    double result = union_size > 0 ? (double)intersection / union_size : 0.0;

    if (used_heap) free(used);
    if (on_heap) { free(bg1); free(bg2); }
    return result;
}

/* --- Cosine Similarity on character bigrams --- */

static double cosine_similarity(const char *s1, const char *s2) {
    int len1 = (int)strlen(s1);
    int len2 = (int)strlen(s2);

    if (len1 == 0 && len2 == 0) return 1.0;
    if (len1 < 2 || len2 < 2) return (strcmp(s1, s2) == 0) ? 1.0 : 0.0;

    /* Direct-indexed bigram frequency vectors — key IS the index */
    #define COS_HASH_SIZE 65536
    static int freq1[COS_HASH_SIZE];
    static int freq2[COS_HASH_SIZE];
    memset(freq1, 0, sizeof(freq1));
    memset(freq2, 0, sizeof(freq2));

    for (int i = 0; i < len1 - 1; i++) {
        unsigned int h = ((unsigned char)s1[i] << 8) | (unsigned char)s1[i+1];
        freq1[h]++;
    }
    for (int i = 0; i < len2 - 1; i++) {
        unsigned int h = ((unsigned char)s2[i] << 8) | (unsigned char)s2[i+1];
        freq2[h]++;
    }

    /* Compute dot product and magnitudes */
    double dot = 0.0, mag1 = 0.0, mag2 = 0.0;
    for (int i = 0; i < COS_HASH_SIZE; i++) {
        if (freq1[i] || freq2[i]) {
            dot += (double)freq1[i] * freq2[i];
            mag1 += (double)freq1[i] * freq1[i];
            mag2 += (double)freq2[i] * freq2[i];
        }
    }
    #undef COS_HASH_SIZE

    if (mag1 < 1e-10 || mag2 < 1e-10) return 0.0;
    return dot / (sqrt(mag1) * sqrt(mag2));
}

/* --- Percentage Difference (numeric) --- */

static double pct_diff(double a, double b) {
    /* ABS(a-b) / max(|a|, |b|) — handles negative values correctly */
    double abs_a = fabs(a), abs_b = fabs(b);
    double max_val = abs_a > abs_b ? abs_a : abs_b;
    if (max_val < 1e-10) return 0.0; /* both ~zero */
    return fabs(a - b) / max_val;
}

/* --- Token Intersection Size --- */
/* Counts shared space-delimited tokens between two strings */

static int token_intersection_size(const char *s1, const char *s2) {
    /* Extract tokens from s1 and s2, count matches */
    #define MAX_TOKENS 128
    #define MAX_TOK_LEN 128
    char toks1[MAX_TOKENS][MAX_TOK_LEN];
    char toks2[MAX_TOKENS][MAX_TOK_LEN];
    int n1 = 0, n2 = 0;

    /* Tokenize s1 */
    {
        char buf[1024];
        strncpy(buf, s1, 1023); buf[1023] = '\0';
        char *tok = strtok(buf, " \t");
        while (tok && n1 < MAX_TOKENS) {
            strncpy(toks1[n1], tok, MAX_TOK_LEN - 1);
            toks1[n1][MAX_TOK_LEN - 1] = '\0';
            n1++;
            tok = strtok(NULL, " \t");
        }
    }
    /* Tokenize s2 */
    {
        char buf[1024];
        strncpy(buf, s2, 1023); buf[1023] = '\0';
        char *tok = strtok(buf, " \t");
        while (tok && n2 < MAX_TOKENS) {
            strncpy(toks2[n2], tok, MAX_TOK_LEN - 1);
            toks2[n2][MAX_TOK_LEN - 1] = '\0';
            n2++;
            tok = strtok(NULL, " \t");
        }
    }

    /* Count intersection */
    int used[MAX_TOKENS];
    memset(used, 0, (size_t)n2 * sizeof(int));
    int count = 0;
    for (int i = 0; i < n1; i++) {
        for (int j = 0; j < n2; j++) {
            if (!used[j] && strcmp(toks1[i], toks2[j]) == 0) {
                count++;
                used[j] = 1;
                break;
            }
        }
    }
    #undef MAX_TOKENS
    #undef MAX_TOK_LEN
    return count;
}

/* ========================================================================
 * Double Metaphone Algorithm (Lawrence Philips, 2000)
 *
 * Generates primary and secondary phonetic codes for English names.
 * This is a simplified but functional implementation covering the
 * major rules needed for name matching.
 * ======================================================================== */

#define META_MAX_LEN 6  /* max phonetic code length */

static int is_vowel(char c) {
    return (c == 'A' || c == 'E' || c == 'I' || c == 'O' || c == 'U' || c == 'Y');
}


static void double_metaphone(const char *input, char *primary, char *secondary) {
    char word[256];
    int len, pos = 0;
    int p_idx = 0, s_idx = 0;

    primary[0] = '\0';
    secondary[0] = '\0';

    if (!input || !input[0]) return;

    /* Uppercase copy */
    strncpy(word, input, 255);
    word[255] = '\0';
    for (int i = 0; word[i]; i++)
        word[i] = (char)toupper((unsigned char)word[i]);
    len = (int)strlen(word);

    /* Skip initial silent letters */
    if (len >= 2) {
        if ((word[0] == 'G' && word[1] == 'N') ||
            (word[0] == 'K' && word[1] == 'N') ||
            (word[0] == 'P' && word[1] == 'N') ||
            (word[0] == 'A' && word[1] == 'E') ||
            (word[0] == 'W' && word[1] == 'R'))
            pos = 1;
    }

    /* Initial X -> S */
    if (word[0] == 'X') {
        primary[p_idx++] = 'S';
        secondary[s_idx++] = 'S';
        pos = 1;
    }

    #define ADD_P(c) do { if (p_idx < META_MAX_LEN) primary[p_idx++] = (c); } while(0)
    #define ADD_S(c) do { if (s_idx < META_MAX_LEN) secondary[s_idx++] = (c); } while(0)
    #define ADD_BOTH(c) do { ADD_P(c); ADD_S(c); } while(0)

    while (pos < len && (p_idx < META_MAX_LEN || s_idx < META_MAX_LEN)) {
        char c = word[pos];
        char next = (pos + 1 < len) ? word[pos + 1] : '\0';
        char next2 = (pos + 2 < len) ? word[pos + 2] : '\0';

        switch (c) {
        case 'A': case 'E': case 'I': case 'O': case 'U':
            if (pos == 0) ADD_BOTH('A');
            pos++;
            break;

        case 'B':
            ADD_BOTH('P');
            pos += (next == 'B') ? 2 : 1;
            break;

        case 'C':
            if (next == 'H') {
                ADD_BOTH('X');
                pos += 2;
            } else if (next == 'I' || next == 'E' || next == 'Y') {
                ADD_BOTH('S');
                pos += 2;
            } else {
                ADD_BOTH('K');
                pos += (next == 'C' && next != 'E' && next != 'I') ? 2 : 1;
            }
            break;

        case 'D':
            if (next == 'G' && (next2 == 'I' || next2 == 'E' || next2 == 'Y')) {
                ADD_BOTH('J');
                pos += 3;
            } else {
                ADD_BOTH('T');
                pos += (next == 'D') ? 2 : 1;
            }
            break;

        case 'F':
            ADD_BOTH('F');
            pos += (next == 'F') ? 2 : 1;
            break;

        case 'G':
            if (next == 'H') {
                if (pos > 0 && !is_vowel(word[pos - 1])) {
                    ADD_BOTH('K');
                } else if (pos == 0) {
                    ADD_BOTH('K');
                }
                pos += 2;
            } else if (next == 'N') {
                if (pos + 2 >= len || (pos + 2 < len && word[pos + 2] == '\0')) {
                    /* silent GN at end */
                } else {
                    ADD_BOTH('K');
                }
                pos += 2;
            } else if (next == 'G') {
                ADD_BOTH('K');
                pos += 2;
            } else if (next == 'I' || next == 'E' || next == 'Y') {
                ADD_P('J');
                ADD_S('K');  /* Germanic: K for secondary */
                pos += 2;
            } else {
                if (pos > 0 || next != '\0') ADD_BOTH('K');
                pos++;
            }
            break;

        case 'H':
            if (is_vowel(next) && (pos == 0 || !is_vowel(word[pos - 1]))) {
                ADD_BOTH('H');
            }
            pos++;
            break;

        case 'J':
            ADD_P('J');
            ADD_S('H');  /* Spanish J -> H */
            pos += (next == 'J') ? 2 : 1;
            break;

        case 'K':
            ADD_BOTH('K');
            pos += (next == 'K') ? 2 : 1;
            break;

        case 'L':
            ADD_BOTH('L');
            pos += (next == 'L') ? 2 : 1;
            break;

        case 'M':
            ADD_BOTH('M');
            pos += (next == 'M') ? 2 : 1;
            break;

        case 'N':
            ADD_BOTH('N');
            pos += (next == 'N') ? 2 : 1;
            break;

        case 'P':
            if (next == 'H') {
                ADD_BOTH('F');
                pos += 2;
            } else {
                ADD_BOTH('P');
                pos += (next == 'P') ? 2 : 1;
            }
            break;

        case 'Q':
            ADD_BOTH('K');
            pos += (next == 'Q') ? 2 : 1;
            break;

        case 'R':
            ADD_BOTH('R');
            pos += (next == 'R') ? 2 : 1;
            break;

        case 'S':
            if (next == 'H') {
                ADD_BOTH('X');
                pos += 2;
            } else if (next == 'I' && (next2 == 'O' || next2 == 'A')) {
                ADD_P('X');
                ADD_S('S');
                pos += 3;
            } else if (next == 'C') {
                if (next2 == 'H') {
                    ADD_P('X');
                    ADD_S('S');
                    pos += 3;
                } else if (next2 == 'I' || next2 == 'E' || next2 == 'Y') {
                    ADD_BOTH('S');
                    pos += 3;
                } else {
                    ADD_BOTH('S');
                    ADD_BOTH('K');
                    pos += 3;
                }
            } else {
                ADD_BOTH('S');
                pos += (next == 'S' || next == 'Z') ? 2 : 1;
            }
            break;

        case 'T':
            if (next == 'H') {
                ADD_BOTH('0');  /* theta -> 0 as placeholder */
                pos += 2;
            } else if (next == 'I' && (next2 == 'O' || next2 == 'A')) {
                ADD_BOTH('X');
                pos += 3;
            } else {
                ADD_BOTH('T');
                pos += (next == 'T') ? 2 : 1;
            }
            break;

        case 'V':
            ADD_BOTH('F');
            pos += (next == 'V') ? 2 : 1;
            break;

        case 'W':
            if (is_vowel(next)) {
                ADD_BOTH('A');
            }
            pos++;
            break;

        case 'X':
            ADD_BOTH('K');
            ADD_BOTH('S');
            pos += (next == 'X') ? 2 : 1;
            break;

        case 'Z':
            ADD_BOTH('S');
            pos += (next == 'Z') ? 2 : 1;
            break;

        default:
            pos++;
            break;
        }
    }

    #undef ADD_P
    #undef ADD_S
    #undef ADD_BOTH

    primary[p_idx] = '\0';
    secondary[s_idx] = '\0';
}

/*
 * Check if two names have a phonetic match via Double Metaphone.
 * Returns 1 if any of the 4 code pairs match (p1==p2, p1==s2, s1==p2, s1==s2).
 */
static int metaphone_match(const char *a, const char *b) {
    char pa[META_MAX_LEN + 1], sa[META_MAX_LEN + 1];
    char pb[META_MAX_LEN + 1], sb[META_MAX_LEN + 1];
    double_metaphone(a, pa, sa);
    double_metaphone(b, pb, sb);

    if (pa[0] && pb[0] && strcmp(pa, pb) == 0) return 1;
    if (pa[0] && sb[0] && strcmp(pa, sb) == 0) return 1;
    if (sa[0] && pb[0] && strcmp(sa, pb) == 0) return 1;
    if (sa[0] && sb[0] && strcmp(sa, sb) == 0) return 1;
    return 0;
}

/*
 * Name comparison with phonetic matching (METHOD_NAME = 11).
 * Python splink NameComparison levels:
 *   4 = exact match
 *   3 = JW ≥ thresh1 (default 0.92)
 *   2 = JW ≥ thresh2 (default 0.88)
 *   1 = JW ≥ thresh3 (default 0.70) OR Double Metaphone match
 *   0 = else
 * Thresholds configurable via CompConfig.thresholds[]
 */
static int compare_name(const char *a, const char *b, const CompConfig *cfg) {
    double t1 = 0.92, t2 = 0.88, t3 = 0.70;
    if (cfg && cfg->n_thresholds >= 1) t1 = cfg->thresholds[0];
    if (cfg && cfg->n_thresholds >= 2) t2 = cfg->thresholds[1];
    if (cfg && cfg->n_thresholds >= 3) t3 = cfg->thresholds[2];

    if (strcmp(a, b) == 0) return 4; /* exact */

    double jw = jaro_winkler_similarity(a, b);
    if (jw >= t1) return 3;
    if (jw >= t2) return 2;

    /* Level 1: JW ≥ t3 OR phonetic match */
    if (jw >= t3) return 1;
    if (metaphone_match(a, b)) return 1;

    return 0;
}

/* ========================================================================
 * Domain-Specific Comparison Functions
 * ======================================================================== */

/*
 * Date of Birth comparison: parse YYYY-MM-DD or YYYYMMDD.
 * Python splink v4 DateOfBirthComparison has 6 levels:
 *   5 = exact match
 *   4 = Damerau-Levenshtein distance ≤ 1 on raw string
 *   3 = within 1 month (≤ 31 days)
 *   2 = within 1 year (≤ 365 days)
 *   1 = within 10 years (≤ 3650 days)
 *   0 = else
 * Returns level directly (not using threshold loop).
 */

/* Convert year/month/day to approximate day count for date arithmetic */
static int date_to_days(int y, int m, int d) {
    /* Simplified: assumes 30.44 days/month, 365.25 days/year */
    return (int)(y * 365.25 + (m - 1) * 30.44 + d);
}

static int compare_dob(const char *a, const char *b) {
    int ya=0, ma=0, da=0, yb=0, mb=0, db=0;

    /* Try YYYY-MM-DD */
    if (sscanf(a, "%d-%d-%d", &ya, &ma, &da) < 3) {
        /* Try YYYYMMDD — validate digits first */
        if (strlen(a) >= 8 && isdigit((unsigned char)a[0]) && isdigit((unsigned char)a[1]) &&
            isdigit((unsigned char)a[2]) && isdigit((unsigned char)a[3]) &&
            isdigit((unsigned char)a[4]) && isdigit((unsigned char)a[5]) &&
            isdigit((unsigned char)a[6]) && isdigit((unsigned char)a[7])) {
            ya = (a[0]-'0')*1000 + (a[1]-'0')*100 + (a[2]-'0')*10 + (a[3]-'0');
            ma = (a[4]-'0')*10 + (a[5]-'0');
            da = (a[6]-'0')*10 + (a[7]-'0');
        } else return 0;
    }
    if (sscanf(b, "%d-%d-%d", &yb, &mb, &db) < 3) {
        if (strlen(b) >= 8 && isdigit((unsigned char)b[0]) && isdigit((unsigned char)b[1]) &&
            isdigit((unsigned char)b[2]) && isdigit((unsigned char)b[3]) &&
            isdigit((unsigned char)b[4]) && isdigit((unsigned char)b[5]) &&
            isdigit((unsigned char)b[6]) && isdigit((unsigned char)b[7])) {
            yb = (b[0]-'0')*1000 + (b[1]-'0')*100 + (b[2]-'0')*10 + (b[3]-'0');
            mb = (b[4]-'0')*10 + (b[5]-'0');
            db = (b[6]-'0')*10 + (b[7]-'0');
        } else return 0;
    }

    /* Level 5: exact match */
    if (ya == yb && ma == mb && da == db) return 5;

    /* Level 4: DL distance ≤ 1 on raw date string */
    int dl = damerau_levenshtein_distance(a, b);
    if (dl <= 1) return 4;

    /* Compute day difference for proximity levels */
    int days_a = date_to_days(ya, ma, da);
    int days_b = date_to_days(yb, mb, db);
    int day_diff = abs(days_a - days_b);

    /* Level 3: within 1 month (≤ 31 days) */
    if (day_diff <= 31) return 3;

    /* Level 2: within 1 year (≤ 365 days) */
    if (day_diff <= 365) return 2;

    /* Level 1: within 10 years (≤ 3650 days) */
    if (day_diff <= 3650) return 1;

    return 0; /* else */
}

/*
 * Email comparison: split at "@".
 * Levels: 0=else, 1=domain-only, 2=JW-username(>0.88), 3=username-exact, 4=exact
 */
static int compare_email(const char *a, const char *b) {
    /* Python splink v4 EmailComparison levels:
     *   4 = exact full email
     *   3 = exact username match (part before @)
     *   2 = JW >= 0.88 on full email
     *   1 = JW >= 0.88 on username part
     *   0 = else */
    if (strcmp(a, b) == 0) return 4; /* exact full email */

    const char *at_a = strchr(a, '@');
    const char *at_b = strchr(b, '@');
    if (!at_a || !at_b) return 0;

    /* Extract usernames */
    char user_a[128], user_b[128];
    int ua_len = (int)(at_a - a);
    int ub_len = (int)(at_b - b);
    if (ua_len > 127) ua_len = 127;
    if (ub_len > 127) ub_len = 127;
    strncpy(user_a, a, (size_t)ua_len); user_a[ua_len] = '\0';
    strncpy(user_b, b, (size_t)ub_len); user_b[ub_len] = '\0';

    if (strcmp(user_a, user_b) == 0) return 3; /* username exact */

    double jw_full = jaro_winkler_similarity(a, b);
    if (jw_full >= 0.88) return 2; /* JW full email */

    double jw_user = jaro_winkler_similarity(user_a, user_b);
    if (jw_user >= 0.88) return 1; /* JW username */

    return 0;
}

/*
 * Postcode comparison: progressive area matching.
 * Assumes space-separated UK postcodes or numeric ZIP.
 * Levels: 0=else, 1=area(first 1-2 chars), 2=district(first 3-4), 3=sector, 4=exact
 */
static int compare_postcode(const char *a, const char *b) {
    if (strcmp(a, b) == 0) return 4; /* exact */

    int la = (int)strlen(a);
    int lb = (int)strlen(b);
    if (la < 2 || lb < 2) return 0;

    /* Sector: everything except last 2 chars */
    if (la >= 4 && lb >= 4 && la == lb) {
        if (strncmp(a, b, (size_t)(la - 2)) == 0) return 3;
    }

    /* District: first 3-4 chars (up to space or digit after letters) */
    int da = la > 4 ? 4 : la;
    int db = lb > 4 ? 4 : lb;
    int dmin = da < db ? da : db;
    if (dmin >= 3 && strncmp(a, b, (size_t)dmin) == 0) return 2;

    /* Area: first 1-2 chars (letters only) */
    int aa = 0; while (aa < la && isalpha((unsigned char)a[aa])) aa++;
    int ab = 0; while (ab < lb && isalpha((unsigned char)b[ab])) ab++;
    if (aa > 0 && aa == ab && strncmp(a, b, (size_t)aa) == 0) return 1;

    return 0;
}

/*
 * Name swap comparison: check both orderings of two name fields.
 * Requires two input values per record: (forename, surname).
 * Called with concatenated "forename\tsurname" strings.
 * Python splink v4 ForenameSurnameComparison levels:
 *   6 = exact match on both forename AND surname (normal order)
 *   5 = columns reversed (forename_l=surname_r AND surname_l=forename_r)
 *   4 = JW >= thresh1 on BOTH forename AND surname (AND, not average)
 *   3 = JW >= thresh2 on BOTH forename AND surname (AND, not average)
 *   2 = exact match on surname only
 *   1 = exact match on forename only
 *   0 = else
 * Thresholds default to 0.92, 0.88 but configurable via CompConfig.thresholds[]
 */
static int compare_nameswap(const char *a, const char *b, const CompConfig *cfg) {
    double thresh1 = 0.92, thresh2 = 0.88;
    if (cfg && cfg->n_thresholds >= 1) thresh1 = cfg->thresholds[0];
    if (cfg && cfg->n_thresholds >= 2) thresh2 = cfg->thresholds[1];

    /* Parse "forename\tsurname" */
    const char *ta = strchr(a, '\t');
    const char *tb = strchr(b, '\t');
    if (!ta || !tb) {
        /* Fallback: single name, use JW */
        if (strcmp(a, b) == 0) return 6;
        double jw = jaro_winkler_similarity(a, b);
        if (jw >= thresh1) return 4;
        if (jw >= thresh2) return 3;
        return 0;
    }

    char fa[128], sa[128], fb[128], sb[128];
    int fla = (int)(ta - a); if (fla > 127) fla = 127;
    strncpy(fa, a, (size_t)fla); fa[fla] = '\0';
    strncpy(sa, ta + 1, 127); sa[127] = '\0';
    int flb = (int)(tb - b); if (flb > 127) flb = 127;
    strncpy(fb, b, (size_t)flb); fb[flb] = '\0';
    strncpy(sb, tb + 1, 127); sb[127] = '\0';

    /* Level 6: Normal order exact (both forename AND surname) */
    if (strcmp(fa, fb) == 0 && strcmp(sa, sb) == 0) return 6;

    /* Level 5: Columns reversed exact */
    if (strcmp(fa, sb) == 0 && strcmp(sa, fb) == 0) return 5;

    /* JW on forename and surname independently (AND logic, not average) */
    double jw_fn = jaro_winkler_similarity(fa, fb);
    double jw_sn = jaro_winkler_similarity(sa, sb);

    /* Level 4: BOTH forename JW >= thresh1 AND surname JW >= thresh1 */
    if (jw_fn >= thresh1 && jw_sn >= thresh1) return 4;

    /* Level 3: BOTH forename JW >= thresh2 AND surname JW >= thresh2 */
    if (jw_fn >= thresh2 && jw_sn >= thresh2) return 3;

    /* Level 2: Exact surname only */
    if (strcmp(sa, sb) == 0) return 2;

    /* Level 1: Exact forename only */
    if (strcmp(fa, fb) == 0) return 1;

    return 0;
}

/*
 * Haversine distance in km from lat/lon pairs.
 * Input: "lat\tlon" strings (tab-separated).
 */
static double haversine_km(double lat1, double lon1, double lat2, double lon2) {
    double R = 6371.0; /* Earth radius in km */
    double dlat = (lat2 - lat1) * 3.14159265358979323846 / 180.0;
    double dlon = (lon2 - lon1) * 3.14159265358979323846 / 180.0;
    double a = sin(dlat/2)*sin(dlat/2) +
               cos(lat1 * 3.14159265358979323846 / 180.0) *
               cos(lat2 * 3.14159265358979323846 / 180.0) *
               sin(dlon/2)*sin(dlon/2);
    double c = 2 * atan2(sqrt(a), sqrt(1-a));
    return R * c;
}

/* ========================================================================
 * Comparison Dispatch
 * ======================================================================== */

/*
 * Compute the comparison level for a pair on field k.
 *
 * Level encoding (Python splink convention):
 *   -1 = null (missing value in either record)
 *    0 = else (below all thresholds, lowest agreement)
 *    1..n_thresholds = fuzzy levels (ascending agreement)
 *    n_thresholds+1 = exact match (highest agreement)
 *
 * n_levels = n_thresholds + 2 (else + thresholds + exact).
 * Null (-1) is not a valid array index; handled specially in EM/scoring.
 *
 * Thresholds are ordered by quality: thresholds[0] is highest quality.
 * For similarity methods: thresholds descend (0.92, 0.80, ...).
 * For distance methods: thresholds ascend (1, 2, 5, ...).
 * First threshold met maps to the highest fuzzy level (n_thresholds).
 */
/* Check if a tab-separated string has any empty component.
 * Returns 1 if starts with tab, ends with tab, or has consecutive tabs.
 * Used for multi-column comparison variables. */
static int has_empty_tab_component(const char *s) {
    if (s[0] == '\t') return 1;
    size_t len = strlen(s);
    if (len > 0 && s[len - 1] == '\t') return 1;
    if (strstr(s, "\t\t")) return 1;
    return 0;
}

static int compute_comparison_level(
    const CompConfig *cfg,
    const char *str_a, const char *str_b,
    double num_a, double num_b,
    int a_missing, int b_missing
) {
    /* Null level */
    if (a_missing || b_missing) return -1;

    /* Domain-specific methods that compute their own levels directly */
    if (cfg->is_string) {
        switch (cfg->method) {
            case METHOD_DOB:
                return compare_dob(str_a, str_b);
            case METHOD_EMAIL:
                return compare_email(str_a, str_b);
            case METHOD_POSTCODE:
                return compare_postcode(str_a, str_b);
            case METHOD_NAMESWAP:
                return compare_nameswap(str_a, str_b, cfg);
            case METHOD_NAME:
                return compare_name(str_a, str_b, cfg);
            case METHOD_DISTANCE: {
                /* Parse "lat\tlon" from tab-separated string inputs */
                double lat1 = 0, lon1 = 0, lat2 = 0, lon2 = 0;
                const char *t1 = strchr(str_a, '\t');
                const char *t2 = strchr(str_b, '\t');
                if (!t1 || !t2) return 0; /* malformed -> else */
                lat1 = atof(str_a);
                lon1 = atof(t1 + 1);
                lat2 = atof(str_b);
                lon2 = atof(t2 + 1);
                /* Exact coordinate match */
                if (lat1 == lat2 && lon1 == lon2)
                    return cfg->n_thresholds + 1;
                double dist = haversine_km(lat1, lon1, lat2, lon2);
                /* Check distance thresholds (ascending: 10, 50, 100 km) */
                for (int t = 0; t < cfg->n_thresholds; t++) {
                    if (dist <= cfg->thresholds[t])
                        return cfg->n_thresholds - t;
                }
                return 0; /* else — beyond all thresholds */
            }
            case METHOD_CUSTOM: {
                /* Custom: level is pre-computed, stored as numeric in str form */
                int custom_level = atoi(str_a);
                int max_level = cfg->n_thresholds + 1; /* n_levels - 1 */
                if (custom_level < 0) custom_level = 0;
                if (custom_level > max_level) custom_level = max_level;
                return custom_level;
            }
            default:
                break; /* fall through to standard comparison */
        }
    }

    if (cfg->is_string) {
        /* Exact match -> highest level */
        if (strcmp(str_a, str_b) == 0) return cfg->n_thresholds + 1;

        /* Compute similarity/distance */
        double sim = 0.0;
        int dist = 0;
        int is_distance = 0;

        switch (cfg->method) {
            case METHOD_JW:
                sim = jaro_winkler_similarity(str_a, str_b);
                break;
            case METHOD_JARO:
                sim = jaro_similarity(str_a, str_b);
                break;
            case METHOD_LEV:
                dist = levenshtein_distance(str_a, str_b);
                is_distance = 1;
                break;
            case METHOD_DL:
                dist = damerau_levenshtein_distance(str_a, str_b);
                is_distance = 1;
                break;
            case METHOD_JACCARD:
                sim = jaccard_similarity(str_a, str_b);
                break;
            case METHOD_COSINE:
                sim = cosine_similarity(str_a, str_b);
                break;
            case METHOD_INTERSECT: {
                /* Token intersection: level = min(intersection_size, n_thresholds+1) */
                int isz = token_intersection_size(str_a, str_b);
                /* Check thresholds (descending size) */
                for (int t = 0; t < cfg->n_thresholds; t++) {
                    if (isz >= (int)cfg->thresholds[t])
                        return cfg->n_thresholds - t;
                }
                return 0; /* else — below all thresholds */
            }
            case METHOD_EXACT:
                /* Not exact (checked above) -> else level */
                return 0;
            default:
                return 0; /* else */
        }

        /* Check thresholds: t=0 (best quality) -> highest fuzzy level.
         * t=0 -> level n_thresholds, t=1 -> n_thresholds-1, etc. */
        if (is_distance) {
            for (int t = 0; t < cfg->n_thresholds; t++) {
                if (dist <= (int)cfg->thresholds[t])
                    return cfg->n_thresholds - t;
            }
        } else {
            for (int t = 0; t < cfg->n_thresholds; t++) {
                if (sim >= cfg->thresholds[t])
                    return cfg->n_thresholds - t;
            }
        }

        return 0; /* else */
    }
    else {
        /* Numeric comparison */
        if (cfg->method == METHOD_CUSTOM) {
            /* Custom: level is pre-computed, stored as numeric value */
            int custom_level = (int)num_a;
            int max_level = cfg->n_thresholds + 1;
            if (custom_level < 0) custom_level = 0;
            if (custom_level > max_level) custom_level = max_level;
            return custom_level;
        }
        if (cfg->method == METHOD_PCT_DIFF) {
            /* Percentage difference: pct = |a-b| / max(a,b), strict < to match Python */
            if (num_a == num_b) return cfg->n_thresholds + 1; /* exact */
            double pd = pct_diff(num_a, num_b);
            /* Thresholds are maximum pct differences (ascending order: 0.01, 0.05, 0.1) */
            for (int t = 0; t < cfg->n_thresholds; t++) {
                if (pd < cfg->thresholds[t])
                    return cfg->n_thresholds - t;
            }
            return 0;
        }
        if (cfg->method == METHOD_ABS_DATE) {
            /* Absolute date difference in days (Stata numeric dates) */
            if (num_a == num_b) return cfg->n_thresholds + 1; /* exact */
            double diff = fabs(num_a - num_b);
            for (int t = 0; t < cfg->n_thresholds; t++) {
                if (diff <= cfg->thresholds[t])
                    return cfg->n_thresholds - t;
            }
            return 0;
        }
        if (cfg->method == METHOD_ABS_TIME) {
            /* Absolute time difference in configured units (Stata %tc = ms) */
            if (num_a == num_b) return cfg->n_thresholds + 1; /* exact */
            double time_diff = fabs(num_a - num_b) / cfg->time_unit_divisor;
            for (int t = 0; t < cfg->n_thresholds; t++) {
                if (time_diff <= cfg->thresholds[t])
                    return cfg->n_thresholds - t;
            }
            return 0;
        }

        if (num_a == num_b) return cfg->n_thresholds + 1; /* exact */

        double diff = fabs(num_a - num_b);
        for (int t = 0; t < cfg->n_thresholds; t++) {
            if (diff <= cfg->thresholds[t])
                return cfg->n_thresholds - t;
        }
        return 0; /* else */
    }
}

/* ========================================================================
 * Configuration Parser
 * ======================================================================== */

/* Forward declaration for V2 parser */
static int parse_config_v2(FILE *f, Config *cfg);

static void config_defaults(Config *cfg) {
    memset(cfg, 0, sizeof(Config));
    cfg->threshold = 0.85;
    cfg->prior = 0.0001;
    cfg->max_iter = 25;
    cfg->max_block_size = 0; /* 0 = no limit (was 5000; now warns instead of truncating) */
    cfg->null_weight = NULL_NEUTRAL;
    cfg->estimate_u = 0;
    cfg->u_max_pairs = 1000000;
    cfg->u_seed = 42;
    cfg->mode = MODE_LEGACY;
    cfg->config_version = 1;
    cfg->recall = 1.0;
    cfg->fix_lambda = 0;
    cfg->em_without_tf = 0;
    cfg->cluster_threshold = -1.0; /* -1 = use threshold */
    cfg->use_weight_threshold = 0;
    cfg->weight_threshold = 0.0;
    cfg->cluster_method = 0;
    cfg->salt_partitions = 0;
    cfg->round_robin_em = 0;
    cfg->em_tol = EM_TOL;
    for (int k = 0; k < MAX_COMP_VARS; k++) {
        cfg->comp[k].null_mode = -1; /* -1 = use global */
        cfg->comp[k].n_input_vars = 1;
        cfg->comp[k].tf_weight = 1.0;
        cfg->comp[k].tf_exact_only = 0;
        cfg->comp[k].time_unit_divisor = 86400000.0; /* default: days */
    }
}

static int parse_config(const char *path, Config *cfg) {
    FILE *f = fopen(path, "r");
    if (!f) {
        SF_error("splink_plugin: cannot open config file\n");
        return -1;
    }

    config_defaults(cfg);

    /* Check for V2 magic header */
    char line[MAX_LINE];
    if (fgets(line, sizeof(line), f)) {
        char *s = str_strip(line);
        if (strncmp(s, "SPLINK_CONFIG_V2", 16) == 0) {
            cfg->config_version = 2;
            int rc = parse_config_v2(f, cfg);
            fclose(f);
            return rc;
        }
        /* Not V2 — rewind and parse as legacy */
        rewind(f);
    }

    int current_comp = -1;

    while (fgets(line, sizeof(line), f)) {
        char *s = str_strip(line);
        if (*s == '\0' || *s == '#') continue;

        /* Section headers */
        if (*s == '[') {
            if (strncmp(s, "[general]", 9) == 0 ||
                strncmp(s, "[MLABEL_M_OVERRIDE]", 19) == 0) {
                current_comp = -1;
            } else if (strncmp(s, "[comparison_", 12) == 0) {
                current_comp = atoi(s + 12);
                if (current_comp >= MAX_COMP_VARS) current_comp = -1;
            }
            continue;
        }

        /* Key=value */
        char *eq = strchr(s, '=');
        if (!eq) continue;
        *eq = '\0';
        char *key = str_strip(s);
        char *val = str_strip(eq + 1);

        if (current_comp < 0) {
            /* General section */
            if (strcmp(key, "n_comp") == 0) {
                cfg->n_comp = atoi(val);
                if (cfg->n_comp > MAX_COMP_VARS) cfg->n_comp = MAX_COMP_VARS;
                if (cfg->n_comp < 0) cfg->n_comp = 0;
            }
            else if (strcmp(key, "n_block_rules") == 0) cfg->n_block_rules = atoi(val);
            else if (strcmp(key, "link_type") == 0) cfg->link_type = atoi(val);
            else if (strcmp(key, "null_weight") == 0) cfg->null_weight = atoi(val);
            else if (strcmp(key, "threshold") == 0) cfg->threshold = atof(val);
            else if (strcmp(key, "prior") == 0) cfg->prior = atof(val);
            else if (strcmp(key, "max_iter") == 0) cfg->max_iter = atoi(val);
            else if (strcmp(key, "max_block_size") == 0) cfg->max_block_size = atoi(val);
            else if (strcmp(key, "verbose") == 0) cfg->verbose = atoi(val);
            else if (strcmp(key, "mode") == 0) cfg->mode = atoi(val);
            else if (strcmp(key, "estimate_u") == 0) cfg->estimate_u = atoi(val);
            else if (strcmp(key, "u_max_pairs") == 0) cfg->u_max_pairs = atoi(val);
            else if (strcmp(key, "u_seed") == 0) cfg->u_seed = atoi(val);
            else if (strcmp(key, "save_pairs") == 0) { strncpy(cfg->save_pairs, val, 511); cfg->save_pairs[511] = '\0'; }
            else if (strcmp(key, "id_var") == 0) {
                strncpy(cfg->id_var_name, val, MAX_VAR_NAME - 1); cfg->id_var_name[MAX_VAR_NAME - 1] = '\0';
                cfg->has_id_var = (val[0] != '\0');
            }
            /* V3 feature parity options */
            else if (strcmp(key, "recall") == 0) cfg->recall = atof(val);
            else if (strcmp(key, "fix_lambda") == 0) cfg->fix_lambda = atoi(val);
            else if (strcmp(key, "em_without_tf") == 0) cfg->em_without_tf = atoi(val);
            else if (strcmp(key, "cluster_threshold") == 0) cfg->cluster_threshold = atof(val);
            else if (strcmp(key, "use_weight_threshold") == 0) cfg->use_weight_threshold = atoi(val);
            else if (strcmp(key, "weight_threshold") == 0) cfg->weight_threshold = atof(val);
            else if (strcmp(key, "cluster_method") == 0) cfg->cluster_method = atoi(val);
            else if (strcmp(key, "salt_partitions") == 0) cfg->salt_partitions = atoi(val);
            else if (strcmp(key, "round_robin_em") == 0) cfg->round_robin_em = atoi(val);
            else if (strcmp(key, "em_tol") == 0) cfg->em_tol = atof(val);
            else if (strcmp(key, "mlabel_mprob") == 0) {
                /* Supervised m-probs: "p0,p1,...|p0,p1,...|..." */
                char mbuf[2048];
                strncpy(mbuf, val, sizeof(mbuf) - 1);
                mbuf[sizeof(mbuf) - 1] = '\0';
                char *comp_tok = mbuf;
                int ck = 0;
                while (comp_tok && ck < cfg->n_comp) {
                    char *next_comp = strchr(comp_tok, '|');
                    if (next_comp) *next_comp++ = '\0';
                    CompConfig *cc2 = &cfg->comp[ck];
                    cc2->fix_m = 1;
                    int lev = 0;
                    char *lev_tok = comp_tok;
                    while (lev_tok && lev < MAX_LEVELS) {
                        char *next_lev = strchr(lev_tok, ',');
                        if (next_lev) *next_lev++ = '\0';
                        cc2->fixed_m[lev] = atof(lev_tok);
                        lev++;
                        lev_tok = next_lev;
                    }
                    ck++;
                    comp_tok = next_comp;
                }
            }
        }
        else {
            /* Comparison section */
            CompConfig *cc = &cfg->comp[current_comp];
            if (strcmp(key, "var_name") == 0) { strncpy(cc->var_name, val, MAX_VAR_NAME - 1); cc->var_name[MAX_VAR_NAME - 1] = '\0'; }
            else if (strcmp(key, "method") == 0) cc->method = atoi(val);
            else if (strcmp(key, "is_string") == 0) cc->is_string = atoi(val);
            else if (strcmp(key, "tf_adjust") == 0) cc->tf_adjust = atoi(val);
            else if (strcmp(key, "tf_min") == 0) cc->tf_min = atof(val);
            else if (strcmp(key, "tf_file") == 0) { strncpy(cc->tf_file, val, 511); cc->tf_file[511] = '\0'; }
            else if (strcmp(key, "fix_m") == 0) cc->fix_m = atoi(val);
            else if (strcmp(key, "fix_u") == 0) cc->fix_u = atoi(val);
            else if (strcmp(key, "fix_m_mask") == 0) cc->fix_m_mask = atoi(val);
            else if (strcmp(key, "fix_u_mask") == 0) cc->fix_u_mask = atoi(val);
            else if (strcmp(key, "thresholds") == 0) {
                /* Parse comma-separated thresholds */
                cc->n_thresholds = 0;
                if (strlen(val) > 0) {
                    char buf[256];
                    strncpy(buf, val, 255); buf[255] = '\0';
                    char *tok = strtok(buf, ",");
                    while (tok && cc->n_thresholds < MAX_THRESHOLDS) {
                        cc->thresholds[cc->n_thresholds++] = atof(tok);
                        tok = strtok(NULL, ",");
                    }
                }
                /* n_levels = else + n_thresholds + exact (null is -1, not in array) */
                cc->n_levels = cc->n_thresholds + 2;
                /* Override n_levels for domain methods with fixed internal levels */
                switch (cc->method) {
                    case METHOD_EXACT:     cc->n_levels = 2; break; /* else + exact */
                    case METHOD_DOB:       cc->n_levels = 6; break; /* else, ≤10yr, ≤1yr, ≤1mo, DL≤1, exact */
                    case METHOD_EMAIL:     cc->n_levels = 5; break; /* else, jw-user, jw-full, user-exact, exact */
                    case METHOD_POSTCODE:  cc->n_levels = 5; break; /* else, area, district, sector, exact */
                    case METHOD_NAMESWAP:  cc->n_levels = 7; break; /* else, fn-exact, sn-exact, jw≥t2-AND, jw≥t1-AND, swap-exact, exact-both */
                    case METHOD_NAME:      cc->n_levels = 5; break; /* else, metaphone/jw-low, jw-mid, jw-high, exact */
                    /* METHOD_DISTANCE uses threshold-based levels: n_thresholds + 2 (already set) */
                    default: break;
                }
            }
            else if (strcmp(key, "fixed_m") == 0) {
                /* Parse comma-separated fixed m probs */
                char buf[256];
                strncpy(buf, val, 255); buf[255] = '\0';
                char *tok = strtok(buf, ",");
                int idx = 0;
                while (tok && idx < MAX_LEVELS) {
                    cc->fixed_m[idx++] = atof(tok);
                    tok = strtok(NULL, ",");
                }
            }
            else if (strcmp(key, "fixed_u") == 0) {
                char buf[256];
                strncpy(buf, val, 255); buf[255] = '\0';
                char *tok = strtok(buf, ",");
                int idx = 0;
                while (tok && idx < MAX_LEVELS) {
                    cc->fixed_u[idx++] = atof(tok);
                    tok = strtok(NULL, ",");
                }
            }
            /* V3 per-comparison options */
            else if (strcmp(key, "null_mode") == 0) cc->null_mode = atoi(val);
            else if (strcmp(key, "tf_weight") == 0) cc->tf_weight = atof(val);
            else if (strcmp(key, "tf_exact_only") == 0) cc->tf_exact_only = atoi(val);
            else if (strcmp(key, "time_unit") == 0) {
                if (strcmp(val, "seconds") == 0) cc->time_unit_divisor = 1000.0;
                else if (strcmp(val, "minutes") == 0) cc->time_unit_divisor = 60000.0;
                else if (strcmp(val, "hours") == 0) cc->time_unit_divisor = 3600000.0;
                else if (strcmp(val, "days") == 0) cc->time_unit_divisor = 86400000.0;
                else cc->time_unit_divisor = 86400000.0; /* default: days */
            }
        }
    }

    fclose(f);
    return 0;
}

/* ========================================================================
 * Config V2 Parser
 *
 * Format: SPLINK_CONFIG_V2 magic header (already consumed), then:
 *   key=value pairs for globals
 *   [BLOCKING]     — rule=<n_vars> <var_indices...>
 *   [COMPARISONS]  — var=<idx> type=... method=... n_levels=... thresholds=... null=... tf=...
 *   [FIXED_M]      — var=<idx> probs=<p0,p1,...>
 *   [FIXED_U]      — var=<idx> probs=<p0,p1,...>
 *   [TF_TABLE:<N>] — <value>\t<freq>
 *   [END]
 * ======================================================================== */

static int parse_config_v2(FILE *f, Config *cfg) {
    char line[MAX_LINE];
    int section = 0; /* 0=header, 1=blocking, 2=comparisons, 3=fixed_m, 4=fixed_u, 5=tf_table */
    int tf_table_var = -1;

    while (fgets(line, sizeof(line), f)) {
        char *s = str_strip(line);
        if (*s == '\0' || *s == '#') continue;

        /* Section headers */
        if (*s == '[') {
            if (strncmp(s, "[BLOCKING]", 10) == 0) { section = 1; continue; }
            if (strncmp(s, "[COMPARISONS]", 13) == 0) { section = 2; continue; }
            if (strncmp(s, "[FIXED_M]", 9) == 0) { section = 3; continue; }
            if (strncmp(s, "[FIXED_U]", 9) == 0) { section = 4; continue; }
            if (strncmp(s, "[TF_TABLE:", 10) == 0) {
                section = 5;
                tf_table_var = atoi(s + 10);
                continue;
            }
            if (strncmp(s, "[ALLVARS]", 9) == 0) { section = 6; continue; }
            if (strncmp(s, "[END]", 5) == 0) break;
            continue;
        }

        if (section == 0) {
            /* Header key=value pairs */
            char *eq = strchr(s, '=');
            if (!eq) continue;
            *eq = '\0';
            char *key = str_strip(s);
            char *val = str_strip(eq + 1);

            if (strcmp(key, "n_comp") == 0) {
                cfg->n_comp = atoi(val);
                if (cfg->n_comp > MAX_COMP_VARS) cfg->n_comp = MAX_COMP_VARS;
                if (cfg->n_comp < 0) cfg->n_comp = 0;
            }
            else if (strcmp(key, "n_block_rules") == 0) cfg->n_block_rules = atoi(val);
            else if (strcmp(key, "n_allvars") == 0) cfg->n_allvars = atoi(val);
            else if (strcmp(key, "has_link") == 0) {
                if (atoi(val)) cfg->link_type = LINK_ONLY;
            }
            else if (strcmp(key, "link_type") == 0) cfg->link_type = atoi(val);
            else if (strcmp(key, "threshold") == 0) cfg->threshold = atof(val);
            else if (strcmp(key, "max_iter") == 0) cfg->max_iter = atoi(val);
            else if (strcmp(key, "prior") == 0) cfg->prior = atof(val);
            else if (strcmp(key, "null_mode") == 0) {
                if (strcmp(val, "neutral") == 0) cfg->null_weight = NULL_NEUTRAL;
                else if (strcmp(val, "penalize") == 0) cfg->null_weight = NULL_PENALIZE;
                else cfg->null_weight = atoi(val);
            }
            else if (strcmp(key, "null_weight") == 0) cfg->null_weight = atoi(val);
            else if (strcmp(key, "verbose") == 0) cfg->verbose = atoi(val);
            else if (strcmp(key, "mode") == 0) cfg->mode = atoi(val);
            else if (strcmp(key, "estimate_u") == 0) cfg->estimate_u = atoi(val);
            else if (strcmp(key, "u_max_pairs") == 0) cfg->u_max_pairs = atoi(val);
            else if (strcmp(key, "u_seed") == 0) cfg->u_seed = atoi(val);
            else if (strcmp(key, "save_pairs") == 0) { strncpy(cfg->save_pairs, val, 511); cfg->save_pairs[511] = '\0'; }
            else if (strcmp(key, "max_block_size") == 0) cfg->max_block_size = atoi(val);
            else if (strcmp(key, "id_var") == 0) {
                strncpy(cfg->id_var_name, val, MAX_VAR_NAME - 1); cfg->id_var_name[MAX_VAR_NAME - 1] = '\0';
                cfg->has_id_var = 1;
            }
            /* V3 feature parity options in V2 format */
            else if (strcmp(key, "recall") == 0) cfg->recall = atof(val);
            else if (strcmp(key, "fix_lambda") == 0) cfg->fix_lambda = atoi(val);
            else if (strcmp(key, "em_without_tf") == 0) cfg->em_without_tf = atoi(val);
            else if (strcmp(key, "cluster_threshold") == 0) cfg->cluster_threshold = atof(val);
            else if (strcmp(key, "use_weight_threshold") == 0) cfg->use_weight_threshold = atoi(val);
            else if (strcmp(key, "weight_threshold") == 0) cfg->weight_threshold = atof(val);
            else if (strcmp(key, "cluster_method") == 0) cfg->cluster_method = atoi(val);
            else if (strcmp(key, "salt_partitions") == 0) cfg->salt_partitions = atoi(val);
            else if (strcmp(key, "round_robin_em") == 0) cfg->round_robin_em = atoi(val);
            else if (strcmp(key, "em_tol") == 0) cfg->em_tol = atof(val);
        }
        else if (section == 1) {
            /* [BLOCKING] — currently handled by .ado passing block keys as variables */
            /* V2 format: rule=<n_vars> <idx1> <idx2> ... */
            /* For now, this section is informational; blocking is still via block key vars */
        }
        else if (section == 2) {
            /* [COMPARISONS] — var=<idx> type=... method=... n_levels=... thresholds=... */
            int var_idx = -1;
            char *p = s;

            /* Parse var=N */
            if (strncmp(p, "var=", 4) == 0) {
                var_idx = atoi(p + 4) - 1; /* convert to 0-indexed */
                if (var_idx < 0 || var_idx >= MAX_COMP_VARS) continue;
            } else continue;

            CompConfig *cc = &cfg->comp[var_idx];

            /* Parse remaining key=value pairs on the same line */
            while ((p = strchr(p, ' ')) != NULL) {
                p++;
                if (strncmp(p, "type=", 5) == 0) {
                    cc->is_string = (strncmp(p + 5, "string", 6) == 0) ? 1 : 0;
                }
                else if (strncmp(p, "method=", 7) == 0) {
                    char *mv = p + 7;
                    if (strncmp(mv, "jw", 2) == 0) cc->method = METHOD_JW;
                    else if (strncmp(mv, "jaro", 4) == 0 && strncmp(mv, "jaro_w", 6) != 0) cc->method = METHOD_JARO;
                    else if (strncmp(mv, "lev", 3) == 0) cc->method = METHOD_LEV;
                    else if (strncmp(mv, "dl", 2) == 0) cc->method = METHOD_DL;
                    else if (strncmp(mv, "jaccard", 7) == 0) cc->method = METHOD_JACCARD;
                    else if (strncmp(mv, "exact", 5) == 0) cc->method = METHOD_EXACT;
                    else if (strncmp(mv, "numeric", 7) == 0) cc->method = METHOD_NUMERIC;
                    else if (strncmp(mv, "distance_km", 11) == 0) cc->method = METHOD_DISTANCE;
                    else if (strncmp(mv, "distance", 8) == 0) cc->method = METHOD_DISTANCE;
                    else if (strncmp(mv, "dob", 3) == 0) cc->method = METHOD_DOB;
                    else if (strncmp(mv, "email", 5) == 0) cc->method = METHOD_EMAIL;
                    else if (strncmp(mv, "postcode", 8) == 0) cc->method = METHOD_POSTCODE;
                    else if (strncmp(mv, "nameswap", 8) == 0) cc->method = METHOD_NAMESWAP;
                    else if (strncmp(mv, "name", 4) == 0) cc->method = METHOD_NAME;
                    else if (strncmp(mv, "custom", 6) == 0) cc->method = METHOD_CUSTOM;
                    else if (strncmp(mv, "abs_time", 8) == 0) cc->method = METHOD_ABS_TIME;
                    else if (strncmp(mv, "abs_date", 8) == 0) cc->method = METHOD_ABS_DATE;
                    else if (strncmp(mv, "cosine", 6) == 0) cc->method = METHOD_COSINE;
                    else if (strncmp(mv, "intersect", 9) == 0) cc->method = METHOD_INTERSECT;
                    else if (strncmp(mv, "pct_diff", 8) == 0 || strncmp(mv, "pctdiff", 7) == 0) cc->method = METHOD_PCT_DIFF;
                    else cc->method = atoi(mv);
                }
                else if (strncmp(p, "n_levels=", 9) == 0) {
                    cc->n_levels = atoi(p + 9);
                }
                else if (strncmp(p, "thresholds=", 11) == 0) {
                    char buf[256];
                    char *end = strchr(p + 11, ' ');
                    int len = end ? (int)(end - p - 11) : (int)strlen(p + 11);
                    if (len > 255) len = 255;
                    strncpy(buf, p + 11, (size_t)len);
                    buf[len] = '\0';
                    cc->n_thresholds = 0;
                    char *tok = strtok(buf, ",");
                    while (tok && cc->n_thresholds < MAX_THRESHOLDS) {
                        cc->thresholds[cc->n_thresholds++] = atof(tok);
                        tok = strtok(NULL, ",");
                    }
                    if (cc->n_levels == 0)
                        cc->n_levels = cc->n_thresholds + 2;
                }
                else if (strncmp(p, "null=", 5) == 0) {
                    if (strncmp(p + 5, "neutral", 7) == 0) cc->null_mode = NULL_NEUTRAL;
                    else if (strncmp(p + 5, "penalize", 8) == 0) cc->null_mode = NULL_PENALIZE;
                }
                else if (strncmp(p, "tf=", 3) == 0) {
                    cc->tf_adjust = atoi(p + 3);
                }
                else if (strncmp(p, "name=", 5) == 0) {
                    char *end2 = strchr(p + 5, ' ');
                    int nlen = end2 ? (int)(end2 - p - 5) : (int)strlen(p + 5);
                    if (nlen >= MAX_VAR_NAME) nlen = MAX_VAR_NAME - 1;
                    strncpy(cc->var_name, p + 5, (size_t)nlen);
                    cc->var_name[nlen] = '\0';
                }
                else if (strncmp(p, "time_unit=", 10) == 0) {
                    const char *tu = p + 10;
                    if (strncmp(tu, "seconds", 7) == 0) cc->time_unit_divisor = 1000.0;
                    else if (strncmp(tu, "minutes", 7) == 0) cc->time_unit_divisor = 60000.0;
                    else if (strncmp(tu, "hours", 5) == 0) cc->time_unit_divisor = 3600000.0;
                    else if (strncmp(tu, "days", 4) == 0) cc->time_unit_divisor = 86400000.0;
                    else cc->time_unit_divisor = 86400000.0; /* default: days */
                }
            }

            /* Set n_levels if not explicitly given */
            if (cc->n_levels == 0) {
                switch (cc->method) {
                    case METHOD_EXACT:     cc->n_levels = 2; break;
                    case METHOD_DOB:       cc->n_levels = 6; break;
                    case METHOD_EMAIL:     cc->n_levels = 5; break;
                    case METHOD_POSTCODE:  cc->n_levels = 5; break;
                    case METHOD_NAMESWAP:  cc->n_levels = 7; break;
                    case METHOD_NAME:      cc->n_levels = 5; break;
                    default:               cc->n_levels = cc->n_thresholds + 2; break;
                }
            }
        }
        else if (section == 3 || section == 4) {
            /* [FIXED_M] or [FIXED_U] — var=<idx> probs=<p0,p1,...> */
            if (strncmp(s, "var=", 4) != 0) continue;
            int var_idx = atoi(s + 4) - 1;
            if (var_idx < 0 || var_idx >= MAX_COMP_VARS) continue;

            char *probs = strstr(s, "probs=");
            if (!probs) continue;
            probs += 6;

            CompConfig *cc = &cfg->comp[var_idx];
            char buf[256];
            strncpy(buf, probs, 255); buf[255] = '\0';
            char *tok = strtok(buf, ",");
            int idx = 0;
            double *arr = (section == 3) ? cc->fixed_m : cc->fixed_u;
            while (tok && idx < MAX_LEVELS) {
                arr[idx++] = atof(tok);
                tok = strtok(NULL, ",");
            }
            if (section == 3) cc->fix_m = 1;
            else cc->fix_u = 1;
        }
        else if (section == 5) {
            /* [TF_TABLE:N] — value\tfreq pairs, handled at load time */
            /* TF tables are loaded from separate files in legacy mode.
             * In V2, they can be inline. For now, store tf_table_var for future use. */
            (void)tf_table_var;
        }
        else if (section == 6) {
            /* [ALLVARS] — var_index=varname mappings */
            char *eq = strchr(s, '=');
            if (!eq) continue;
            *eq = '\0';
            int vi = atoi(s) - 1;
            if (vi >= 0 && vi < MAX_COMP_VARS) {
                strncpy(cfg->comp[vi].var_name, str_strip(eq + 1), MAX_VAR_NAME - 1);
                cfg->comp[vi].var_name[MAX_VAR_NAME - 1] = '\0';
            }
        }
    }

    return 0;
}

/* ========================================================================
 * Block-Key Sort Comparator
 * ======================================================================== */

static char **g_sort_keys;

static int compare_by_key(const void *a, const void *b) {
    int ia = *(const int *)a;
    int ib = *(const int *)b;
    return strcmp(g_sort_keys[ia], g_sort_keys[ib]);
}

/* ========================================================================
 * Pair Hash Set for Deduplication across blocking rules
 * ======================================================================== */

#define PAIR_HASH_INIT  16384

typedef struct {
    int64_t *keys;    /* encoded as (a << 32) | b, a < b */
    int     *rule_id; /* blocking rule index that first created this pair */
    int      cap;
    int      n;
} PairSet;

static PairSet *pairset_create(int init_cap) {
    PairSet *ps = malloc(sizeof(PairSet));
    if (!ps) return NULL;
    if (init_cap < PAIR_HASH_INIT) init_cap = PAIR_HASH_INIT;
    ps->keys = calloc((size_t)init_cap, sizeof(int64_t));
    ps->rule_id = calloc((size_t)init_cap, sizeof(int));
    if (!ps->keys || !ps->rule_id) {
        free(ps->keys); free(ps->rule_id); free(ps); return NULL;
    }
    /* Initialize with sentinel */
    memset(ps->keys, 0xFF, (size_t)init_cap * sizeof(int64_t));
    ps->cap = init_cap;
    ps->n = 0;
    return ps;
}

static int64_t pair_encode(int a, int b) {
    if (a > b) { int t = a; a = b; b = t; }
    return ((int64_t)a << 32) | (int64_t)b;
}

static int pairset_insert(PairSet *ps, int a, int b, int rule) {
    /* Returns 1 if newly inserted, 0 if already existed, -1 on OOM.
     * Stores the blocking rule index for the first insertion. */
    if (!ps) return -1;
    if (ps->n * 2 >= ps->cap) {
        /* Grow */
        int new_cap = ps->cap * 2;
        int64_t *new_keys = calloc((size_t)new_cap, sizeof(int64_t));
        int *new_rule_id = calloc((size_t)new_cap, sizeof(int));
        if (!new_keys || !new_rule_id) { free(new_keys); free(new_rule_id); return -1; }
        memset(new_keys, 0xFF, (size_t)new_cap * sizeof(int64_t));
        /* Rehash */
        for (int i = 0; i < ps->cap; i++) {
            if (ps->keys[i] != (int64_t)-1) {
                uint64_t h = (uint64_t)ps->keys[i] * 2654435761ULL;
                int slot = (int)(h % (uint64_t)new_cap);
                while (new_keys[slot] != (int64_t)-1)
                    slot = (slot + 1) % new_cap;
                new_keys[slot] = ps->keys[i];
                new_rule_id[slot] = ps->rule_id[i];
            }
        }
        free(ps->keys);
        free(ps->rule_id);
        ps->keys = new_keys;
        ps->rule_id = new_rule_id;
        ps->cap = new_cap;
    }

    int64_t key = pair_encode(a, b);
    uint64_t h = (uint64_t)key * 2654435761ULL;
    int slot = (int)(h % (uint64_t)ps->cap);
    while (ps->keys[slot] != (int64_t)-1) {
        if (ps->keys[slot] == key) return 0; /* exists */
        slot = (slot + 1) % ps->cap;
    }
    ps->keys[slot] = key;
    ps->rule_id[slot] = rule;
    ps->n++;
    return 1;
}

static void pairset_free(PairSet *ps) {
    if (!ps) return;
    free(ps->keys);
    free(ps->rule_id);
    free(ps);
}

/* ========================================================================
 * Union-Find (Disjoint Set) for Clustering
 * ======================================================================== */

typedef struct {
    int *parent;
    int *rank;
    int n;
} UnionFind;

static UnionFind *uf_create(int n) {
    UnionFind *uf = malloc(sizeof(UnionFind));
    if (!uf) return NULL;
    uf->parent = malloc((size_t)n * sizeof(int));
    uf->rank   = calloc((size_t)n, sizeof(int));
    uf->n      = n;
    if (!uf->parent || !uf->rank) {
        if (uf->parent) free(uf->parent);
        if (uf->rank)   free(uf->rank);
        free(uf);
        return NULL;
    }
    for (int i = 0; i < n; i++) uf->parent[i] = i;
    return uf;
}

static int uf_find(UnionFind *uf, int x) {
    while (uf->parent[x] != x) {
        uf->parent[x] = uf->parent[uf->parent[x]];
        x = uf->parent[x];
    }
    return x;
}

static void uf_union(UnionFind *uf, int x, int y) {
    int rx = uf_find(uf, x);
    int ry = uf_find(uf, y);
    if (rx == ry) return;
    if (uf->rank[rx] < uf->rank[ry]) { int t = rx; rx = ry; ry = t; }
    uf->parent[ry] = rx;
    if (uf->rank[rx] == uf->rank[ry]) uf->rank[rx]++;
}

static void uf_free(UnionFind *uf) {
    if (!uf) return;
    free(uf->parent);
    free(uf->rank);
    free(uf);
}

/* ========================================================================
 * EM Algorithm — Variable-Length Levels with Null Handling
 * ======================================================================== */

/*
 * comp_vectors: [n_pairs * n_comp] level indices per pair per field
 * m, u: m[k] and u[k] point to arrays of size n_levels[k]
 *   Level 0 is null: m[k][0] = u[k][0] = fixed (not estimated)
 * lambda: prior match probability (in/out)
 * p_match: [n_pairs] posterior match probabilities (output)
 * tf_tables: [n_comp] TF tables (NULL if no TF for that field)
 * tf_pair_values: [n_pairs][n_comp] matched value strings for TF lookup
 * tf_record_freq: [n_comp][n_records] pre-computed TF frequencies per record
 * pair_a, pair_b: [n_pairs] record indices for each pair (for tf_record_freq lookup)
 *
 * Returns: number of EM iterations, or -1 on error.
 */
static int em_estimate(
    const int *comp_vectors,
    int n_pairs,
    int n_comp,
    const int *n_levels,
    double **m,
    double **u,
    double *lambda,
    double *p_match,
    int max_iter,
    double tol,
    int verbose,
    int null_weight,
    const CompConfig *comp_cfg,
    TFTable **tf_tables,
    char ***tf_pair_values,
    double **tf_record_freq,
    const int *pair_a,
    const int *pair_b,
    int fix_lambda,
    int em_without_tf
) {
    int converged_iter = max_iter;

    /* Allocate sufficient statistics */
    double **m_count = calloc((size_t)n_comp, sizeof(double *));
    double **u_count = calloc((size_t)n_comp, sizeof(double *));
    double *m_denom = calloc((size_t)n_comp, sizeof(double));
    double *u_denom = calloc((size_t)n_comp, sizeof(double));

    if (!m_count || !u_count || !m_denom || !u_denom) goto em_fail;

    for (int k = 0; k < n_comp; k++) {
        m_count[k] = calloc((size_t)n_levels[k], sizeof(double));
        u_count[k] = calloc((size_t)n_levels[k], sizeof(double));
        if (!m_count[k] || !u_count[k]) goto em_fail;
    }

    for (int iter = 0; iter < max_iter; iter++) {
        double max_change = 0.0;

        /* --- E-step: P(match | comparison vector) --- */
        for (int i = 0; i < n_pairs; i++) {
            double log_m_prod = 0.0;
            double log_u_prod = 0.0;

            for (int k = 0; k < n_comp; k++) {
                int level = comp_vectors[i * n_comp + k];

                /* Null handling: per-comparison override or global */
                if (level == -1) {
                    int nm = (comp_cfg[k].null_mode >= 0) ? comp_cfg[k].null_mode : null_weight;
                    if (nm == NULL_NEUTRAL) {
                        /* Skip: Bayes factor = 1 (no contribution) */
                        continue;
                    } else {
                        /* Penalize: treat as else (level 0) */
                        level = 0;
                    }
                }

                double mk = m[k][level];
                double uk = u[k][level];

                /* TF adjustment: Python splink v4 applies TF as a multiplicative
                 * factor on the Bayes factor: tf_factor = pow(u_exact / tf, w).
                 * Final BF = (m/u) * tf_factor.
                 * tf_exact_only: only apply TF at exact-match level.
                 * tf_weight: exponent on the adjustment ratio (Python convention). */
                double log_tf_factor = 0.0;
                int apply_tf = comp_cfg[k].tf_adjust && level > 0 && !em_without_tf;
                if (apply_tf && comp_cfg[k].tf_exact_only && level != n_levels[k] - 1)
                    apply_tf = 0;
                if (apply_tf) {
                    double tf = 0.0;
                    int have_tf = 0;
                    if (tf_record_freq && tf_record_freq[k] && pair_a && pair_b) {
                        double tf_a = tf_record_freq[k][pair_a[i]];
                        double tf_b = tf_record_freq[k][pair_b[i]];
                        if (level == n_levels[k] - 1) {
                            tf = tf_a;
                        } else {
                            tf = tf_a > tf_b ? tf_a : tf_b;
                        }
                        have_tf = 1;
                    } else if (level == n_levels[k] - 1 && tf_tables && tf_tables[k] &&
                               tf_pair_values && tf_pair_values[i]) {
                        char *val = tf_pair_values[i][k];
                        if (val && val[0] != '\0') {
                            tf = tf_lookup(tf_tables[k], val, uk > 0 ? uk : 0.01);
                            have_tf = 1;
                        }
                    }
                    if (have_tf) {
                        if (tf < comp_cfg[k].tf_min && comp_cfg[k].tf_min > 0)
                            tf = comp_cfg[k].tf_min;
                        if (tf < 1e-10) tf = 1e-10;
                        /* Python formula: tf_factor = pow(u_exact / tf, w) */
                        double u_exact = u[k][n_levels[k] - 1];
                        if (u_exact < 1e-10) u_exact = 1e-10;
                        double w = comp_cfg[k].tf_weight;
                        log_tf_factor = w * log(u_exact / tf);
                    }
                }

                if (mk < 1e-10) mk = 1e-10;
                if (uk < 1e-10) uk = 1e-10;
                log_m_prod += log(mk) + log_tf_factor;
                log_u_prod += log(uk);
            }

            double log_num = log(*lambda) + log_m_prod;
            double log_den_other = log(1.0 - *lambda) + log_u_prod;

            double log_den;
            if (log_num > log_den_other)
                log_den = log_num + log1p(exp(log_den_other - log_num));
            else
                log_den = log_den_other + log1p(exp(log_num - log_den_other));

            p_match[i] = exp(log_num - log_den);
        }

        /* --- M-step --- */
        for (int k = 0; k < n_comp; k++) {
            memset(m_count[k], 0, (size_t)n_levels[k] * sizeof(double));
            memset(u_count[k], 0, (size_t)n_levels[k] * sizeof(double));
        }
        memset(m_denom, 0, (size_t)n_comp * sizeof(double));
        memset(u_denom, 0, (size_t)n_comp * sizeof(double));

        double sum_p = 0.0;
        for (int i = 0; i < n_pairs; i++) {
            double pm = p_match[i];
            sum_p += pm;
            for (int k = 0; k < n_comp; k++) {
                int level = comp_vectors[i * n_comp + k];
                /* Null handling: per-comparison override or global */
                if (level == -1) {
                    int nm = (comp_cfg[k].null_mode >= 0) ? comp_cfg[k].null_mode : null_weight;
                    if (nm == NULL_NEUTRAL) continue;
                    else level = 0; /* penalize -> else */
                }
                m_count[k][level] += pm;
                u_count[k][level] += (1.0 - pm);
                m_denom[k] += pm;
                u_denom[k] += (1.0 - pm);
            }
        }

        /* Update lambda (unless fix_lambda is set) */
        if (!fix_lambda) {
            double new_lambda = sum_p / n_pairs;
            if (new_lambda < 1e-8) new_lambda = 1e-8;
            if (new_lambda > 1.0 - 1e-8) new_lambda = 1.0 - 1e-8;

            double dl = fabs(*lambda - new_lambda);
            if (dl > max_change) max_change = dl;
            *lambda = new_lambda;
        }

        /* Update m and u per field per level (all levels 0..n_levels-1) */
        for (int k = 0; k < n_comp; k++) {
            for (int l = 0; l < n_levels[k]; l++) {
                /* Per-level fix check: mask bit overrides, else use fix_m boolean */
                int m_fixed = comp_cfg[k].fix_m;
                if (comp_cfg[k].fix_m_mask && l < 32)
                    m_fixed = (comp_cfg[k].fix_m_mask >> l) & 1;
                int u_fixed = comp_cfg[k].fix_u;
                if (comp_cfg[k].fix_u_mask && l < 32)
                    u_fixed = (comp_cfg[k].fix_u_mask >> l) & 1;

                if (!m_fixed) {
                    double new_mk = m_denom[k] > 0
                        ? m_count[k][l] / m_denom[k]
                        : 1.0 / n_levels[k];
                    double dm = fabs(m[k][l] - new_mk);
                    if (dm > max_change) max_change = dm;
                    m[k][l] = new_mk;
                }
                if (!u_fixed) {
                    double new_uk = u_denom[k] > 0
                        ? u_count[k][l] / u_denom[k]
                        : 1.0 / n_levels[k];
                    double du = fabs(u[k][l] - new_uk);
                    if (du > max_change) max_change = du;
                    u[k][l] = new_uk;
                }
            }
        }

        /* Record iteration history */
        if (iter < EM_MAX_HISTORY) {
            em_hist_lambda[iter] = *lambda;
            em_hist_maxchange[iter] = max_change;
            em_hist_n = iter + 1;
        }

        if (verbose) {
            char buf[256];
            snprintf(buf, sizeof(buf),
                "  EM iteration %d: max_change=%.6f lambda=%.6f\n",
                iter + 1, max_change, *lambda);
            SF_display(buf);
        }

        if (max_change < tol) {
            converged_iter = iter + 1;
            break;
        }
    }

    /* Cleanup */
    for (int k = 0; k < n_comp; k++) {
        if (m_count && m_count[k]) free(m_count[k]);
        if (u_count && u_count[k]) free(u_count[k]);
    }
    free(m_count); free(u_count); free(m_denom); free(u_denom);
    return converged_iter;

em_fail:
    if (m_count) { for (int k = 0; k < n_comp; k++) if (m_count[k]) free(m_count[k]); free(m_count); }
    if (u_count) { for (int k = 0; k < n_comp; k++) if (u_count[k]) free(u_count[k]); free(u_count); }
    free(m_denom); free(u_denom);
    return -1;
}

/* ========================================================================
 * Random u Estimation (Splink-style unbiased u via random sampling)
 * ======================================================================== */

/*
 * XorShift128+ RNG for random pair sampling.
 * Fast, statistically sound, and deterministic given seed.
 */
typedef struct { uint64_t s[2]; } XorShift128;

static void xorshift_seed(XorShift128 *rng, uint64_t seed) {
    rng->s[0] = seed | 1;
    rng->s[1] = (seed * 6364136223846793005ULL + 1442695040888963407ULL) | 1;
}

static uint64_t xorshift_next(XorShift128 *rng) {
    uint64_t s1 = rng->s[0];
    uint64_t s0 = rng->s[1];
    rng->s[0] = s0;
    s1 ^= s1 << 23;
    rng->s[1] = s1 ^ s0 ^ (s1 >> 17) ^ (s0 >> 26);
    return rng->s[1] + s0;
}

/*
 * Estimate u-probabilities via random (unblocked) pair sampling.
 *
 * Draws up to max_pairs random pairs (without blocking), computes
 * comparison levels, and estimates u[k][level] as empirical frequencies.
 * This gives an unbiased estimate of u since random pairs are overwhelmingly
 * non-matches (unlike blocked pairs which are biased toward matches).
 *
 * Sets u_params[k][level] and marks cfg->comp[k].fix_u = 1 for all k.
 */
static int estimate_u_random(
    int n,
    int n_comp,
    const CompConfig *comp_cfg,
    char ***str_comp,
    double **num_comp,
    double *link_source,
    int link_type,
    double **u_params,
    const int *n_levels_arr,
    int max_pairs,
    int seed,
    int verbose
) {
    XorShift128 rng;
    xorshift_seed(&rng, (uint64_t)seed);

    /* Allocate level counts and per-field non-null pair counts */
    double **level_counts = calloc((size_t)n_comp, sizeof(double *));
    double *field_nonnull = calloc((size_t)n_comp, sizeof(double));
    if (!level_counts || !field_nonnull) {
        free(level_counts);
        free(field_nonnull);
        return -1;
    }
    for (int k = 0; k < n_comp; k++) {
        level_counts[k] = calloc((size_t)n_levels_arr[k], sizeof(double));
        if (!level_counts[k]) {
            for (int j = 0; j < k; j++) free(level_counts[j]);
            free(level_counts);
            free(field_nonnull);
            return -1;
        }
    }

    int actual_pairs = 0;
    int attempts = 0;
    int max_attempts = max_pairs * 5; /* avoid infinite loop on tiny datasets */

    while (actual_pairs < max_pairs && attempts < max_attempts) {
        attempts++;

        /* Draw two random observations */
        int ai = (int)(xorshift_next(&rng) % (uint64_t)n);
        int bi = (int)(xorshift_next(&rng) % (uint64_t)(n - 1));
        if (bi >= ai) bi++; /* ensure ai != bi */

        /* Link mode: skip same-source pairs for LINK_ONLY */
        if (link_type == LINK_ONLY && link_source &&
            link_source[ai] == link_source[bi])
            continue;

        /* Compute comparison levels */
        for (int k = 0; k < n_comp; k++) {
            int a_missing, b_missing;
            const char *str_a = NULL, *str_b = NULL;
            double num_a = 0, num_b = 0;

            if (comp_cfg[k].is_string) {
                str_a = str_comp[k][ai];
                str_b = str_comp[k][bi];
                a_missing = (str_a[0] == '\0');
                b_missing = (str_b[0] == '\0');
            } else {
                num_a = num_comp[k][ai];
                num_b = num_comp[k][bi];
                a_missing = SF_is_missing(num_a);
                b_missing = SF_is_missing(num_b);
            }

            int level = compute_comparison_level(
                &comp_cfg[k], str_a, str_b, num_a, num_b, a_missing, b_missing);

            /* Null (-1): skip, don't count toward this field */
            if (level == -1) continue;
            if (level >= n_levels_arr[k]) level = n_levels_arr[k] - 1;

            level_counts[k][level] += 1.0;
            field_nonnull[k] += 1.0;
        }
        actual_pairs++;
    }

    if (actual_pairs == 0) {
        for (int k = 0; k < n_comp; k++) free(level_counts[k]);
        free(level_counts);
        free(field_nonnull);
        return -1;
    }

    /* Convert counts to frequencies (u-probabilities).
     * Normalize per-field by non-null pair count so u-probs sum to ~1.0
     * even when some fields have missing values. */
    for (int k = 0; k < n_comp; k++) {
        double denom = field_nonnull[k] > 0 ? field_nonnull[k] : 1.0;
        for (int l = 0; l < n_levels_arr[k]; l++) {
            double freq = level_counts[k][l] / denom;
            /* Floor at a small value to prevent zero-division in BF */
            if (freq < 1e-6) freq = 1e-6;
            u_params[k][l] = freq;
        }
    }

    if (verbose) {
        char buf[256];
        snprintf(buf, sizeof(buf),
            "splink: estimated u from %d random pairs (seed=%d)\n",
            actual_pairs, seed);
        SF_display(buf);

        for (int k = 0; k < n_comp; k++) {
            snprintf(buf, sizeof(buf), "  field %d u:", k);
            SF_display(buf);
            for (int l = 0; l < n_levels_arr[k]; l++) {
                snprintf(buf, sizeof(buf), " %.4f", u_params[k][l]);
                SF_display(buf);
            }
            SF_display("\n");
        }
    }

    for (int k = 0; k < n_comp; k++) free(level_counts[k]);
    free(level_counts);
    free(field_nonnull);
    return actual_pairs;
}

/* ========================================================================
 * Lambda Estimation (deterministic)
 *
 * Estimates the probability of two random records being a match (lambda)
 * by counting pairs where all comparisons are at exact-match level.
 * lambda = n_deterministic_matches / total_pairs
 * ======================================================================== */

static double estimate_lambda_deterministic(
    const int *comp_vec,
    long long n_pairs,
    int n_comp,
    const int *n_levels,
    double assumed_recall
) {
    if (n_pairs == 0) return 0.0001;

    long long det_matches = 0;
    for (long long i = 0; i < n_pairs; i++) {
        int all_exact = 1;
        for (int k = 0; k < n_comp; k++) {
            int level = comp_vec[i * n_comp + k];
            if (level != n_levels[k] - 1) { /* not exact */
                all_exact = 0;
                break;
            }
        }
        if (all_exact) det_matches++;
    }

    /* lambda = count / (total * recall_adjustment) */
    double recall = assumed_recall > 0 ? assumed_recall : 1.0;
    double lam = (double)det_matches / ((double)n_pairs * recall);
    if (lam < 1e-8) lam = 1e-8;
    if (lam > 0.99) lam = 0.99;
    return lam;
}

/* ========================================================================
 * Main Entry Point
 * ======================================================================== */

STDLL stata_call(int argc, char *argv[]) {
    /* Pointers for cleanup */
    Config    cfg;
    char    **block_keys_all = NULL;   /* [n_block_rules * n] flattened */
    char   ***str_comp       = NULL;
    double  **num_comp       = NULL;
    double   *link_source    = NULL;
    int      *sorted_idx     = NULL;
    int      *pair_a         = NULL;
    int      *pair_b         = NULL;
    int      *comp_vec       = NULL;
    double  **m_params       = NULL;
    double  **u_params       = NULL;
    int      *n_levels       = NULL;
    double   *p_match        = NULL;
    UnionFind *uf            = NULL;
    int      *root_to_cid    = NULL;
    PairSet  *pairset        = NULL;
    TFTable **tf_tables      = NULL;
    char   ***tf_pair_values = NULL;
    int      *match_key      = NULL;   /* blocking rule index per pair */
    char    **id_values       = NULL;   /* string ID values per record */
    double   *id_num_values   = NULL;   /* numeric ID values per record */
    int       id_is_string    = 0;     /* 1 if ID variable is string */

    int rc = 0;
    int n = 0;
    long long total_pairs = 0;
    int n_matches = 0;
    int n_clusters = 0;
    double lambda = 0;
    int em_iters = 0;
    int out_var = 0;
    int comp_start = 0;
    int link_var = 0;
    char *diag_path = NULL;

    /* ---- 0. Parse arguments and config ---- */
    if (argc < 2) {
        SF_error("splink_plugin requires 2 arguments: config_path diag_path\n");
        return 198;
    }

    if (parse_config(argv[0], &cfg) != 0) return 198;
    diag_path = argv[1];

    n = (int)SF_nobs();
    lambda = cfg.prior;

    /* Variable positions:
     * block_keys(1..n_block_rules), compvars, [linkvar], [idvar], generate */
    comp_start = cfg.n_block_rules + 1;
    int has_link = (cfg.link_type == LINK_ONLY || cfg.link_type == LINK_AND_DEDUPE);
    link_var = has_link ? comp_start + cfg.n_comp : 0;
    int id_var = 0;
    if (cfg.has_id_var) {
        id_var = cfg.n_block_rules + cfg.n_comp + (has_link ? 1 : 0) + 1;
        out_var = id_var + 1;
    } else {
        out_var = cfg.n_block_rules + cfg.n_comp + (has_link ? 1 : 0) + 1;
    }

    if (cfg.verbose) {
        char buf[512];
        snprintf(buf, sizeof(buf),
            "splink: n=%d n_comp=%d n_block_rules=%d link_type=%d threshold=%.3f prior=%.6f\n",
            n, cfg.n_comp, cfg.n_block_rules, cfg.link_type, cfg.threshold, cfg.prior);
        SF_display(buf);
    }

    if (n < 2) {
        SF_error("splink_plugin: need at least 2 observations\n");
        return 2000;
    }

    /* ---- 1. Read block keys ---- */
    block_keys_all = calloc((size_t)cfg.n_block_rules * (size_t)n, sizeof(char *));
    if (!block_keys_all) { SF_error("splink_plugin: out of memory\n"); rc = 909; goto cleanup; }

    for (int r = 0; r < cfg.n_block_rules; r++) {
        for (int i = 0; i < n; i++) {
            int idx = r * n + i;
            block_keys_all[idx] = malloc(MAX_STR_LEN);
            if (!block_keys_all[idx]) { rc = 909; goto cleanup; }
            SF_sdata(r + 1, i + 1, block_keys_all[idx]);
            str_trim(block_keys_all[idx]);
            str_tolower(block_keys_all[idx]);
        }
    }

    /* ---- 2. Read comparison variables ---- */
    str_comp = calloc((size_t)cfg.n_comp, sizeof(char **));
    num_comp = calloc((size_t)cfg.n_comp, sizeof(double *));
    if (!str_comp || !num_comp) { rc = 909; goto cleanup; }

    for (int k = 0; k < cfg.n_comp; k++) {
        int var_idx = comp_start + k;
        if (cfg.comp[k].is_string) {
            str_comp[k] = malloc((size_t)n * sizeof(char *));
            if (!str_comp[k]) { rc = 909; goto cleanup; }
            memset(str_comp[k], 0, (size_t)n * sizeof(char *));

            for (int i = 0; i < n; i++) {
                str_comp[k][i] = malloc(MAX_STR_LEN);
                if (!str_comp[k][i]) { rc = 909; goto cleanup; }
                SF_sdata(var_idx, i + 1, str_comp[k][i]);
                str_trim(str_comp[k][i]);
                str_tolower(str_comp[k][i]);
            }
        } else {
            num_comp[k] = malloc((size_t)n * sizeof(double));
            if (!num_comp[k]) { rc = 909; goto cleanup; }

            for (int i = 0; i < n; i++) {
                ST_double val;
                SF_vdata(var_idx, i + 1, &val);
                num_comp[k][i] = val;
            }
        }
    }

    /* ---- 3. Read link source (if linking mode) ---- */
    if (has_link) {
        if (SF_var_is_string(link_var)) {
            SF_error("splink error: linkvar must be a numeric variable\n");
            rc = 198; goto cleanup;
        }
        link_source = malloc((size_t)n * sizeof(double));
        if (!link_source) { rc = 909; goto cleanup; }
        for (int i = 0; i < n; i++) {
            ST_double val;
            SF_vdata(link_var, i + 1, &val);
            link_source[i] = val;
        }
    }

    /* ---- 3b. Read ID variable (if specified) ---- */
    if (cfg.has_id_var && id_var > 0) {
        /* Determine if string or numeric */
        if (SF_var_is_string(id_var)) {
            id_is_string = 1;
            id_values = calloc((size_t)n, sizeof(char *));
            if (!id_values) { rc = 909; goto cleanup; }
            for (int i = 0; i < n; i++) {
                char buf[MAX_STR_LEN];
                if (SF_sdata(id_var, i + 1, buf) == 0) {
                    id_values[i] = strdup(buf);
                } else {
                    id_values[i] = strdup("");
                }
                if (!id_values[i]) { rc = 909; goto cleanup; }
            }
        } else {
            id_is_string = 0;
            id_num_values = malloc((size_t)n * sizeof(double));
            if (!id_num_values) { rc = 909; goto cleanup; }
            for (int i = 0; i < n; i++) {
                ST_double val;
                SF_vdata(id_var, i + 1, &val);
                id_num_values[i] = val;
            }
        }
    }

    /* ---- 4. Load TF tables + pre-compute per-record TF frequencies ---- */
    tf_tables = calloc((size_t)cfg.n_comp, sizeof(TFTable *));
    if (!tf_tables) { rc = 909; goto cleanup; }

    for (int k = 0; k < cfg.n_comp; k++) {
        if (cfg.comp[k].tf_adjust && cfg.comp[k].tf_file[0] != '\0') {
            tf_tables[k] = tf_load_file(cfg.comp[k].tf_file);
            if (cfg.verbose && tf_tables[k]) {
                char buf[256];
                snprintf(buf, sizeof(buf), "  Loaded TF table for field %d: %d entries\n",
                    k, tf_tables[k]->n_entries);
                SF_display(buf);
            }
        }
    }

    /* Pre-compute per-record TF frequencies for O(1) pair lookup.
     * tf_record_freq[k][i] = TF frequency of record i's value on field k.
     * Enables fuzzy TF: use max(tf_a, tf_b) for non-exact matches. */
    double **tf_record_freq = NULL;
    {
        int any_tf = 0;
        for (int k = 0; k < cfg.n_comp; k++)
            if (cfg.comp[k].tf_adjust && tf_tables[k]) { any_tf = 1; break; }

        if (any_tf) {
            tf_record_freq = calloc((size_t)cfg.n_comp, sizeof(double *));
            if (tf_record_freq) {
                for (int k = 0; k < cfg.n_comp; k++) {
                    if (!cfg.comp[k].tf_adjust || !tf_tables[k]) continue;
                    tf_record_freq[k] = malloc((size_t)n * sizeof(double));
                    if (!tf_record_freq[k]) continue;
                    for (int i = 0; i < n; i++) {
                        if (cfg.comp[k].is_string && str_comp[k]) {
                            double def_u = 1.0 / n; /* default for unseen values */
                            tf_record_freq[k][i] = tf_lookup(tf_tables[k],
                                str_comp[k][i], def_u);
                        } else if (!cfg.comp[k].is_string && num_comp[k]) {
                            /* Numeric: convert to string for TF lookup */
                            double val = num_comp[k][i];
                            if (SF_is_missing(val)) {
                                tf_record_freq[k][i] = 1.0 / n;
                            } else {
                                char numbuf[64];
                                snprintf(numbuf, sizeof(numbuf), "%g", val);
                                double def_u = 1.0 / n;
                                tf_record_freq[k][i] = tf_lookup(tf_tables[k],
                                    numbuf, def_u);
                            }
                        } else {
                            tf_record_freq[k][i] = 1.0 / n;
                        }
                    }
                }
            }
        }
    }

    /* ---- 5. Generate pairs from all blocking rules (OR + dedup) ---- */
    pairset = pairset_create(PAIR_HASH_INIT);
    if (!pairset) { rc = 909; goto cleanup; }

    sorted_idx = malloc((size_t)n * sizeof(int));
    if (!sorted_idx) { rc = 909; goto cleanup; }

    /* First pass: count total unique pairs */
    for (int r = 0; r < cfg.n_block_rules; r++) {
        char **bkeys = block_keys_all + (r * n);

        for (int i = 0; i < n; i++) sorted_idx[i] = i;
        g_sort_keys = bkeys;
        qsort(sorted_idx, (size_t)n, sizeof(int), compare_by_key);

        int bs = 0;
        while (bs < n) {
            int be = bs + 1;
            while (be < n && strcmp(bkeys[sorted_idx[bs]], bkeys[sorted_idx[be]]) == 0)
                be++;

            /* Skip empty block keys */
            if (bkeys[sorted_idx[bs]][0] == '\0') { bs = be; continue; }

            int bsz = be - bs;
            int max_bs = cfg.max_block_size > 0 ? cfg.max_block_size : bsz;
            int eff = bsz > max_bs ? max_bs : bsz;
            if (eff < bsz) {
                char wbuf[512];
                snprintf(wbuf, sizeof(wbuf),
                    "{txt}splink WARNING: block '%.*s' has %d records (limit=%d), "
                    "truncating to %lld pairs\n",
                    60, bkeys[sorted_idx[bs]], bsz, max_bs,
                    (long long)eff * ((long long)eff - 1) / 2);
                SF_display(wbuf);
            }

            for (int i = bs; i < bs + eff; i++) {
                for (int j = i + 1; j < bs + eff; j++) {
                    int ai = sorted_idx[i];
                    int bj = sorted_idx[j];

                    /* Link mode: skip same-source pairs */
                    if (cfg.link_type == LINK_ONLY && has_link &&
                        link_source[ai] == link_source[bj])
                        continue;

                    /* link_and_dedupe: keep all pairs */

                    /* Blocking salting: skip pairs where salt_a != salt_b */
                    if (cfg.salt_partitions > 0) {
                        int salt_a = ai % cfg.salt_partitions;
                        int salt_b = bj % cfg.salt_partitions;
                        if (salt_a != salt_b) continue;
                    }

                    pairset_insert(pairset, ai, bj, r);
                }
            }
            bs = be;
        }
    }

    total_pairs = pairset->n;

    if (total_pairs > (long long)INT_MAX) {
        char buf[256];
        snprintf(buf, sizeof(buf),
            "splink warning: %lld pairs exceeds int range; clamping to %d\n",
            (long long)total_pairs, INT_MAX);
        SF_display(buf);
        total_pairs = INT_MAX;
    }

    if (cfg.verbose) {
        char buf[256];
        snprintf(buf, sizeof(buf), "splink: %lld unique candidate pairs from %d blocking rule(s)\n",
            (long long)total_pairs, cfg.n_block_rules);
        SF_display(buf);
    }

    /* Adaptive prior floor for small datasets.
     * With very few candidate pairs, the user-specified prior (e.g., 0.0001)
     * can dominate the EM, preventing convergence. Ensure at least ~1 expected
     * match in the initial E-step. This matches splink's practical behavior
     * on large datasets while being robust for small ones. */
    {
        double lambda_floor = 1.0 / (2.0 * (double)total_pairs);
        if (lambda_floor > 0.5) lambda_floor = 0.5;
        if (lambda < lambda_floor) {
            if (cfg.verbose) {
                char buf[256];
                snprintf(buf, sizeof(buf),
                    "splink: adaptive prior: raising lambda from %.6f to %.6f (%lld pairs)\n",
                    lambda, lambda_floor, (long long)total_pairs);
                SF_display(buf);
            }
            lambda = lambda_floor;
        }
    }

    /* Handle zero-pairs case */
    if (total_pairs == 0) {
        if (cfg.verbose) SF_display("splink: no candidate pairs, assigning unique clusters\n");
        for (int i = 0; i < n; i++)
            SF_vstore(out_var, i + 1, (double)(i + 1));
        n_clusters = n;

        FILE *df = fopen(diag_path, "w");
        if (df) {
            fprintf(df, "n_pairs=0\nn_matches=0\nn_clusters=%d\nlambda=0\nem_iterations=0\n", n);
            fclose(df);
        }
        goto cleanup;
    }

    /* ---- 6. Extract pairs from hash set into arrays ---- */
    pair_a = malloc((size_t)total_pairs * sizeof(int));
    pair_b = malloc((size_t)total_pairs * sizeof(int));
    match_key = malloc((size_t)total_pairs * sizeof(int));
    if (!pair_a || !pair_b || !match_key) { rc = 909; goto cleanup; }

    {
        int pidx = 0;
        for (int slot = 0; slot < pairset->cap; slot++) {
            if (pairset->keys[slot] != (int64_t)-1) {
                int64_t key = pairset->keys[slot];
                pair_a[pidx] = (int)(key >> 32);
                pair_b[pidx] = (int)(key & 0xFFFFFFFF);
                match_key[pidx] = pairset->rule_id[slot];
                pidx++;
            }
        }
    }

    /* Free pair set — no longer needed */
    pairset_free(pairset);
    pairset = NULL;

    /* ---- 7. Compute comparison vectors ---- */
    comp_vec = malloc((size_t)total_pairs * (size_t)cfg.n_comp * sizeof(int));
    if (!comp_vec) { rc = 909; goto cleanup; }

    /* Prepare n_levels array — validate each comparison has >= 2 levels */
    n_levels = malloc((size_t)cfg.n_comp * sizeof(int));
    if (!n_levels) { rc = 909; goto cleanup; }
    for (int k = 0; k < cfg.n_comp; k++) {
        n_levels[k] = cfg.comp[k].n_levels;
        if (n_levels[k] < 2) {
            char buf[256];
            snprintf(buf, sizeof(buf),
                "splink error: comparison %d has %d levels (minimum 2 required)\n",
                k, n_levels[k]);
            SF_display(buf);
            rc = 198; goto cleanup;
        }
    }

    /* Allocate TF pair value storage (for exact-match pairs on TF fields) */
    {
        int any_tf = 0;
        for (int k = 0; k < cfg.n_comp; k++)
            if (cfg.comp[k].tf_adjust) { any_tf = 1; break; }

        if (any_tf) {
            tf_pair_values = calloc((size_t)total_pairs, sizeof(char **));
            if (!tf_pair_values) { rc = 909; goto cleanup; }
        }
    }

    for (long long i = 0; i < total_pairs; i++) {
        int ai = pair_a[i];
        int bi = pair_b[i];
        int has_tf_for_pair = 0;

        for (int k = 0; k < cfg.n_comp; k++) {
            int a_missing, b_missing;
            const char *str_a = NULL, *str_b = NULL;
            double num_a = 0, num_b = 0;

            if (cfg.comp[k].is_string) {
                str_a = str_comp[k][ai];
                str_b = str_comp[k][bi];
                a_missing = (str_a[0] == '\0');
                b_missing = (str_b[0] == '\0');
                /* Multi-column vars use tab separators; empty component = missing */
                if (!a_missing && strchr(str_a, '\t'))
                    a_missing = has_empty_tab_component(str_a);
                if (!b_missing && strchr(str_b, '\t'))
                    b_missing = has_empty_tab_component(str_b);
            } else {
                num_a = num_comp[k][ai];
                num_b = num_comp[k][bi];
                a_missing = SF_is_missing(num_a);
                b_missing = SF_is_missing(num_b);
            }

            int level = compute_comparison_level(
                &cfg.comp[k], str_a, str_b, num_a, num_b, a_missing, b_missing);

            /* Clamp level to valid range (but preserve -1 for null) */
            if (level >= n_levels[k]) level = n_levels[k] - 1;

            comp_vec[i * cfg.n_comp + k] = level;

            /* Store value for TF lookup on exact matches (max level) */
            if (level == n_levels[k] - 1 && cfg.comp[k].tf_adjust) {
                if (!tf_pair_values[i]) {
                    tf_pair_values[i] = calloc((size_t)cfg.n_comp, sizeof(char *));
                }
                if (tf_pair_values[i]) {
                    if (cfg.comp[k].is_string) {
                        tf_pair_values[i][k] = (char *)str_a; /* borrowed ptr */
                    } else {
                        /* Numeric: convert to string for TF (must free later) */
                        char numbuf[64];
                        snprintf(numbuf, sizeof(numbuf), "%g", num_a);
                        tf_pair_values[i][k] = strdup(numbuf);
                    }
                }
                has_tf_for_pair = 1;
            }
        }
        (void)has_tf_for_pair;
    }

    /* ---- 8. Initialize and run EM ---- */
    m_params = calloc((size_t)cfg.n_comp, sizeof(double *));
    u_params = calloc((size_t)cfg.n_comp, sizeof(double *));
    if (!m_params || !u_params) { rc = 909; goto cleanup; }

    for (int k = 0; k < cfg.n_comp; k++) {
        int nl = n_levels[k];
        m_params[k] = calloc((size_t)nl, sizeof(double));
        u_params[k] = calloc((size_t)nl, sizeof(double));
        if (!m_params[k] || !u_params[k]) { rc = 909; goto cleanup; }

        /* Initialize m/u priors.
         * New encoding: 0=else, 1..n_thresholds=fuzzy, n_thresholds+1=exact.
         * Null (-1) is not in the array. */
        if (cfg.comp[k].fix_m) {
            for (int l = 0; l < nl; l++)
                m_params[k][l] = cfg.comp[k].fixed_m[l];
        } else {
            /* Level nl-1 (exact): high m */
            m_params[k][nl - 1] = 0.85;
            /* Distribute remaining across else (0) and fuzzy (1..nl-2) */
            double rem = 0.15;
            for (int l = 0; l < nl - 1; l++)
                m_params[k][l] = rem / (nl - 1 > 0 ? nl - 1 : 1);
        }

        if (cfg.comp[k].fix_u) {
            for (int l = 0; l < nl; l++)
                u_params[k][l] = cfg.comp[k].fixed_u[l];
        } else {
            /* Level nl-1 (exact): low u */
            u_params[k][nl - 1] = 0.01;
            /* Level 0 (else): high u */
            u_params[k][0] = 0.85;
            /* Middle fuzzy levels */
            double rem = 0.14;
            for (int l = 1; l < nl - 1; l++)
                u_params[k][l] = rem / (nl - 2 > 0 ? nl - 2 : 1);
        }
    }

    /* ---- 8b. Random u estimation (Splink-style, if requested) ---- */
    /* MODE_TRAIN always estimates u */
    if (cfg.mode == MODE_TRAIN) cfg.estimate_u = 1;

    if (cfg.estimate_u) {
        int u_pairs = estimate_u_random(
            n, cfg.n_comp, cfg.comp,
            str_comp, num_comp, link_source,
            cfg.link_type, u_params, n_levels,
            cfg.u_max_pairs, cfg.u_seed, cfg.verbose);

        if (u_pairs > 0) {
            /* Fix u during EM (Splink default behavior) */
            for (int k = 0; k < cfg.n_comp; k++)
                cfg.comp[k].fix_u = 1;

            if (cfg.verbose) {
                char buf[256];
                snprintf(buf, sizeof(buf),
                    "splink: u fixed from %d random pairs; EM will only estimate m\n",
                    u_pairs);
                SF_display(buf);
            }
        } else {
            SF_display("{txt}splink WARNING: random u estimation failed, using EM for both m and u\n");
        }
    }

    p_match = malloc((size_t)total_pairs * sizeof(double));
    if (!p_match) { rc = 909; goto cleanup; }

    /* MODE_GAMMA: output comparison vectors only, no EM or scoring */
    if (cfg.mode == MODE_GAMMA) {
        if (cfg.verbose)
            SF_display("splink: MODE_GAMMA — outputting gamma vectors only\n");
        if (cfg.save_pairs[0] != '\0') {
            FILE *gf = fopen(cfg.save_pairs, "w");
            if (gf) {
                /* Header: obs_a, obs_b, gamma_0, gamma_1, ..., gamma_{n-1} */
                fprintf(gf, "obs_a,obs_b");
                for (int k = 0; k < cfg.n_comp; k++)
                    fprintf(gf, ",gamma_%d", k);
                fprintf(gf, "\n");
                for (long long i = 0; i < total_pairs; i++) {
                    fprintf(gf, "%d,%d", pair_a[i] + 1, pair_b[i] + 1);
                    for (int k = 0; k < cfg.n_comp; k++)
                        fprintf(gf, ",%d", comp_vec[i * cfg.n_comp + k]);
                    fprintf(gf, "\n");
                }
                fclose(gf);
            }
        }
        /* Return total_pairs in r(npairs) via Stata scalar */
        char buf[256];
        snprintf(buf, sizeof(buf), "%lld", total_pairs);
        SF_scal_save("_splink_npairs", (double)total_pairs);
        rc = 0; goto cleanup;
    }

    /* MODE_SCORE: skip EM entirely, use provided fixed params for scoring */
    if (cfg.mode == MODE_SCORE) {
        if (cfg.verbose)
            SF_display("splink: MODE_SCORE — skipping EM, using fixed parameters\n");
        em_iters = 0;

        /* Compute p_match using fixed params (single E-step) */
        for (long long i = 0; i < total_pairs; i++) {
            double log_m_prod = 0.0, log_u_prod = 0.0;
            for (int k = 0; k < cfg.n_comp; k++) {
                int level = comp_vec[i * cfg.n_comp + k];
                if (level == -1) {
                    int nm = (cfg.comp[k].null_mode >= 0) ? cfg.comp[k].null_mode : cfg.null_weight;
                    if (nm == NULL_NEUTRAL) continue;
                    else level = 0;
                }
                double mk = m_params[k][level];
                double uk = u_params[k][level];
                /* TF adjustment: multiplicative factor pow(u_exact/tf, w) */
                double log_tf_factor = 0.0;
                int apply_tf = cfg.comp[k].tf_adjust && level > 0;
                if (apply_tf && cfg.comp[k].tf_exact_only && level != n_levels[k] - 1)
                    apply_tf = 0;
                if (apply_tf) {
                    double tf = 0.0;
                    int have_tf = 0;
                    if (tf_record_freq && tf_record_freq[k]) {
                        double tf_a = tf_record_freq[k][pair_a[i]];
                        double tf_b = tf_record_freq[k][pair_b[i]];
                        tf = (level == n_levels[k] - 1) ? tf_a : (tf_a > tf_b ? tf_a : tf_b);
                        have_tf = 1;
                    } else if (level == n_levels[k] - 1 && tf_tables && tf_tables[k] &&
                               tf_pair_values && tf_pair_values[i]) {
                        char *val = tf_pair_values[i][k];
                        if (val && val[0] != '\0') {
                            tf = tf_lookup(tf_tables[k], val, uk > 0 ? uk : 0.01);
                            have_tf = 1;
                        }
                    }
                    if (have_tf) {
                        if (tf < cfg.comp[k].tf_min && cfg.comp[k].tf_min > 0)
                            tf = cfg.comp[k].tf_min;
                        if (tf < 1e-10) tf = 1e-10;
                        double u_exact = u_params[k][n_levels[k] - 1];
                        if (u_exact < 1e-10) u_exact = 1e-10;
                        double w = cfg.comp[k].tf_weight;
                        log_tf_factor = w * log(u_exact / tf);
                    }
                }
                if (mk < 1e-10) mk = 1e-10;
                if (uk < 1e-10) uk = 1e-10;
                log_m_prod += log(mk) + log_tf_factor;
                log_u_prod += log(uk);
            }
            double log_num = log(lambda) + log_m_prod;
            double log_den_other = log(1.0 - lambda) + log_u_prod;
            double log_den;
            if (log_num > log_den_other)
                log_den = log_num + log1p(exp(log_den_other - log_num));
            else
                log_den = log_den_other + log1p(exp(log_num - log_den_other));
            p_match[i] = exp(log_num - log_den);
        }
        goto post_em;
    }

    if (cfg.verbose) SF_display("splink: running EM estimation...\n");

    if (cfg.round_robin_em && cfg.n_block_rules > 1) {
        /* Round-robin EM: train per blocking rule, then average m/u parameters */
        if (cfg.verbose) SF_display("splink: round-robin EM across blocking rules...\n");

        /* Accumulate m/u sums for averaging */
        double **m_sum = calloc((size_t)cfg.n_comp, sizeof(double *));
        double **u_sum = calloc((size_t)cfg.n_comp, sizeof(double *));
        if (!m_sum || !u_sum) { rc = 909; goto cleanup; }
        for (int k = 0; k < cfg.n_comp; k++) {
            m_sum[k] = calloc((size_t)n_levels[k], sizeof(double));
            u_sum[k] = calloc((size_t)n_levels[k], sizeof(double));
            if (!m_sum[k] || !u_sum[k]) { rc = 909; goto cleanup; }
        }

        double lambda_sum = 0.0;
        int n_rules_used = 0;

        for (int rule = 0; rule < cfg.n_block_rules; rule++) {
            /* Count pairs for this rule */
            int rule_count = 0;
            for (int i = 0; i < (int)total_pairs; i++) {
                if (match_key[i] == rule) rule_count++;
            }
            if (rule_count < 2) continue; /* skip rules with too few pairs */

            /* Build subset arrays */
            int *sub_comp = malloc((size_t)rule_count * (size_t)cfg.n_comp * sizeof(int));
            int *sub_pair_a = malloc((size_t)rule_count * sizeof(int));
            int *sub_pair_b = malloc((size_t)rule_count * sizeof(int));
            double *sub_p_match = calloc((size_t)rule_count, sizeof(double));
            char ***sub_tf_vals = NULL;
            double **sub_tf_freq = NULL;

            if (!sub_comp || !sub_pair_a || !sub_pair_b || !sub_p_match) {
                free(sub_comp); free(sub_pair_a); free(sub_pair_b); free(sub_p_match);
                rc = 909; goto cleanup;
            }

            /* Build TF subset arrays if TF is active.
             * tf_pair_values is [pair][comp], tf_record_freq is [comp][global_record].
             * sub_tf_vals must also be [subset_pair][comp] for em_estimate.
             * tf_record_freq can be passed directly since sub_pair_a holds global indices. */
            if (tf_pair_values) {
                sub_tf_vals = calloc((size_t)rule_count, sizeof(char **));
                if (!sub_tf_vals) { rc = 909; goto cleanup; }
            }

            int si = 0;
            for (int i = 0; i < (int)total_pairs; i++) {
                if (match_key[i] != rule) continue;
                memcpy(&sub_comp[si * cfg.n_comp], &comp_vec[i * cfg.n_comp],
                       (size_t)cfg.n_comp * sizeof(int));
                sub_pair_a[si] = pair_a[i];
                sub_pair_b[si] = pair_b[i];
                if (tf_pair_values && tf_pair_values[i]) {
                    sub_tf_vals[si] = tf_pair_values[i]; /* share pointer: [pair][comp] */
                }
                si++;
            }

            /* Initialize per-rule m/u from current params */
            double **rule_m = calloc((size_t)cfg.n_comp, sizeof(double *));
            double **rule_u = calloc((size_t)cfg.n_comp, sizeof(double *));
            for (int k = 0; k < cfg.n_comp; k++) {
                rule_m[k] = malloc((size_t)n_levels[k] * sizeof(double));
                rule_u[k] = malloc((size_t)n_levels[k] * sizeof(double));
                memcpy(rule_m[k], m_params[k], (size_t)n_levels[k] * sizeof(double));
                memcpy(rule_u[k], u_params[k], (size_t)n_levels[k] * sizeof(double));
            }
            double rule_lambda = lambda;

            /* Pass tf_record_freq directly — sub_pair_a holds global record indices,
             * so em_estimate's tf_record_freq[k][pair_a[i]] lookups remain correct. */
            int rule_iters = em_estimate(sub_comp, rule_count, cfg.n_comp,
                                         n_levels, rule_m, rule_u, &rule_lambda,
                                         sub_p_match, cfg.max_iter, cfg.em_tol,
                                         0, cfg.null_weight, cfg.comp,
                                         tf_tables, sub_tf_vals, tf_record_freq,
                                         sub_pair_a, sub_pair_b,
                                         cfg.fix_lambda, cfg.em_without_tf);

            if (rule_iters >= 0) {
                for (int k = 0; k < cfg.n_comp; k++) {
                    for (int l = 0; l < n_levels[k]; l++) {
                        m_sum[k][l] += rule_m[k][l];
                        u_sum[k][l] += rule_u[k][l];
                    }
                }
                lambda_sum += rule_lambda;
                n_rules_used++;
            }

            /* Cleanup per-rule allocations */
            for (int k = 0; k < cfg.n_comp; k++) {
                free(rule_m[k]); free(rule_u[k]);
            }
            free(rule_m); free(rule_u);
            free(sub_comp); free(sub_pair_a); free(sub_pair_b); free(sub_p_match);
            /* sub_tf_vals entries are shared pointers to tf_pair_values[i] — don't free them */
            free(sub_tf_vals);
        }

        /* Average parameters across rules */
        if (n_rules_used > 0) {
            for (int k = 0; k < cfg.n_comp; k++) {
                for (int l = 0; l < n_levels[k]; l++) {
                    m_params[k][l] = m_sum[k][l] / n_rules_used;
                    u_params[k][l] = u_sum[k][l] / n_rules_used;
                }
            }
            lambda = lambda_sum / n_rules_used;
            em_iters = cfg.max_iter; /* mark as complete */
        }

        for (int k = 0; k < cfg.n_comp; k++) {
            free(m_sum[k]); free(u_sum[k]);
        }
        free(m_sum); free(u_sum);

        if (cfg.verbose) {
            char buf[256];
            snprintf(buf, sizeof(buf),
                "splink: round-robin EM used %d/%d rules, averaged lambda=%.6f\n",
                n_rules_used, cfg.n_block_rules, lambda);
            SF_display(buf);
        }

        /* Recompute p_match with averaged parameters on all pairs */
        for (int i = 0; i < (int)total_pairs; i++) {
            double log_m_prod = 0.0, log_u_prod = 0.0;
            for (int k = 0; k < cfg.n_comp; k++) {
                int level = comp_vec[i * cfg.n_comp + k];
                if (level == -1) {
                    int nm = (cfg.comp[k].null_mode >= 0) ? cfg.comp[k].null_mode : cfg.null_weight;
                    if (nm == NULL_NEUTRAL) continue;
                    else level = 0;
                }
                double mk = m_params[k][level];
                double uk = u_params[k][level];
                /* TF adjustment: multiplicative factor pow(u_exact/tf, w) */
                double log_tf_factor = 0.0;
                int apply_tf = cfg.comp[k].tf_adjust && level > 0;
                if (apply_tf && cfg.comp[k].tf_exact_only && level != n_levels[k] - 1)
                    apply_tf = 0;
                if (apply_tf) {
                    double tf = 0.0;
                    int have_tf = 0;
                    if (tf_record_freq && tf_record_freq[k]) {
                        double tf_a = tf_record_freq[k][pair_a[i]];
                        double tf_b = tf_record_freq[k][pair_b[i]];
                        tf = (level == n_levels[k] - 1) ? tf_a : (tf_a > tf_b ? tf_a : tf_b);
                        have_tf = 1;
                    } else if (level == n_levels[k] - 1 && tf_tables && tf_tables[k] &&
                               tf_pair_values && tf_pair_values[i]) {
                        char *val = tf_pair_values[i][k];
                        if (val && val[0] != '\0') {
                            tf = tf_lookup(tf_tables[k], val, uk > 0 ? uk : 0.01);
                            have_tf = 1;
                        }
                    }
                    if (have_tf) {
                        if (tf < cfg.comp[k].tf_min && cfg.comp[k].tf_min > 0)
                            tf = cfg.comp[k].tf_min;
                        if (tf < 1e-10) tf = 1e-10;
                        double u_exact = u_params[k][n_levels[k] - 1];
                        if (u_exact < 1e-10) u_exact = 1e-10;
                        double w = cfg.comp[k].tf_weight;
                        log_tf_factor = w * log(u_exact / tf);
                    }
                }
                if (mk < 1e-10) mk = 1e-10;
                if (uk < 1e-10) uk = 1e-10;
                log_m_prod += log(mk) + log_tf_factor;
                log_u_prod += log(uk);
            }
            double log_num = log(lambda) + log_m_prod;
            double log_den_other = log(1.0 - lambda) + log_u_prod;
            double log_den;
            if (log_num > log_den_other)
                log_den = log_num + log1p(exp(log_den_other - log_num));
            else
                log_den = log_den_other + log1p(exp(log_num - log_den_other));
            p_match[i] = exp(log_num - log_den);
        }
    } else {
        em_hist_n = 0; /* Reset history for main EM run */
        em_iters = em_estimate(comp_vec, (int)total_pairs, cfg.n_comp,
                               n_levels, m_params, u_params, &lambda, p_match,
                               cfg.max_iter, cfg.em_tol, cfg.verbose,
                               cfg.null_weight, cfg.comp,
                               tf_tables, tf_pair_values,
                               tf_record_freq, pair_a, pair_b,
                               cfg.fix_lambda, cfg.em_without_tf);
    }

    if (em_iters < 0) {
        SF_error("splink_plugin: EM failed (out of memory)\n");
        rc = 909; goto cleanup;
    }

    if (cfg.verbose) {
        char buf[256];
        snprintf(buf, sizeof(buf),
            "splink: EM converged in %d iterations, lambda=%.6f\n",
            em_iters, lambda);
        SF_display(buf);
    }

    /* MODE_TRAIN: estimate lambda deterministically after EM */
    if (cfg.mode == MODE_TRAIN) {
        double det_lambda = estimate_lambda_deterministic(
            comp_vec, total_pairs, cfg.n_comp, n_levels, cfg.recall);
        if (cfg.verbose) {
            char buf[256];
            snprintf(buf, sizeof(buf),
                "splink: MODE_TRAIN deterministic lambda=%.8f (EM lambda=%.8f)\n",
                det_lambda, lambda);
            SF_display(buf);
        }
        lambda = det_lambda;
    }

post_em:
    /* ---- 9. Compute final match weights and probabilities ---- */
    /* Recompute with TF adjustments for final scoring */
    /* (already done in last E-step, p_match is current) */

    /* ---- 10. Save pairwise output if requested ---- */
    /* match_weight = log2(Bayes factor) = sum of per-field log2(m/u)
     * This matches Splink's definition (excludes the prior).
     * match_probability is computed from BF and lambda for consistency. */
    if (cfg.save_pairs[0] != '\0') {
        FILE *pf = fopen(cfg.save_pairs, "w");
        if (pf) {
            /* Header: use variable names when available, else numeric index.
             * Columns: unique_id_l, unique_id_r (or obs_a, obs_b),
             * match_weight, match_probability,
             * gamma_{name}..., bf_{name}..., match_key,
             * [tf_{name}_l, tf_{name}_r, bf_tf_adj_{name} for TF fields] */
            if (cfg.has_id_var)
                fprintf(pf, "unique_id_l,unique_id_r");
            else
                fprintf(pf, "obs_a,obs_b");
            fprintf(pf, ",match_weight,match_probability");
            for (int k = 0; k < cfg.n_comp; k++) {
                if (cfg.comp[k].var_name[0])
                    fprintf(pf, ",gamma_%s", cfg.comp[k].var_name);
                else
                    fprintf(pf, ",gamma_%d", k);
            }
            for (int k = 0; k < cfg.n_comp; k++) {
                if (cfg.comp[k].var_name[0])
                    fprintf(pf, ",bf_%s", cfg.comp[k].var_name);
                else
                    fprintf(pf, ",bf_%d", k);
            }
            fprintf(pf, ",match_key");
            for (int k = 0; k < cfg.n_comp; k++) {
                if (cfg.comp[k].tf_adjust) {
                    if (cfg.comp[k].var_name[0])
                        fprintf(pf, ",tf_%s_l,tf_%s_r,bf_tf_adj_%s",
                            cfg.comp[k].var_name, cfg.comp[k].var_name, cfg.comp[k].var_name);
                    else
                        fprintf(pf, ",tf_%d_l,tf_%d_r,bf_tf_adj_%d", k, k, k);
                }
            }
            fprintf(pf, "\n");

            for (long long i = 0; i < total_pairs; i++) {
                double total_log2_bf = 0.0;
                double bf_vals[MAX_COMP_VARS];
                double tf_l_vals[MAX_COMP_VARS];
                double tf_r_vals[MAX_COMP_VARS];
                double bf_tf_adj[MAX_COMP_VARS];
                memset(tf_l_vals, 0, sizeof(tf_l_vals));
                memset(tf_r_vals, 0, sizeof(tf_r_vals));
                memset(bf_tf_adj, 0, sizeof(bf_tf_adj));

                for (int k = 0; k < cfg.n_comp; k++) {
                    int level = comp_vec[i * cfg.n_comp + k];

                    /* Null handling for pairwise output: per-comparison override */
                    if (level == -1) {
                        int nm = (cfg.comp[k].null_mode >= 0) ? cfg.comp[k].null_mode : cfg.null_weight;
                        if (nm == NULL_NEUTRAL) {
                            bf_vals[k] = 0.0; /* log2(1) = 0, neutral */
                            continue;
                        } else {
                            level = 0; /* penalize -> else */
                        }
                    }

                    double mk = m_params[k][level];
                    double uk = u_params[k][level];

                    /* TF adjustment: multiplicative factor pow(u_exact/tf, w) */
                    {
                        int do_tf = cfg.comp[k].tf_adjust && level > 0;
                        if (do_tf && cfg.comp[k].tf_exact_only && level != n_levels[k] - 1)
                            do_tf = 0;
                        if (do_tf) {
                            double tf = 0.0;
                            int have_tf = 0;
                            if (tf_record_freq && tf_record_freq[k]) {
                                double tf_a = tf_record_freq[k][pair_a[i]];
                                double tf_b = tf_record_freq[k][pair_b[i]];
                                tf_l_vals[k] = tf_a;
                                tf_r_vals[k] = tf_b;
                                tf = (level == n_levels[k] - 1) ? tf_a : (tf_a > tf_b ? tf_a : tf_b);
                                have_tf = 1;
                            } else if (level == n_levels[k] - 1 && tf_tables && tf_tables[k] &&
                                       tf_pair_values && tf_pair_values[i]) {
                                char *val = tf_pair_values[i][k];
                                if (val && val[0] != '\0') {
                                    tf = tf_lookup(tf_tables[k], val, uk > 0 ? uk : 0.01);
                                    tf_l_vals[k] = tf;
                                    tf_r_vals[k] = tf;
                                    have_tf = 1;
                                }
                            }
                            if (have_tf) {
                                if (tf < cfg.comp[k].tf_min && cfg.comp[k].tf_min > 0)
                                    tf = cfg.comp[k].tf_min;
                                if (tf < 1e-10) tf = 1e-10;
                                double u_exact = u_params[k][n_levels[k] - 1];
                                if (u_exact < 1e-10) u_exact = 1e-10;
                                double w = cfg.comp[k].tf_weight;
                                /* TF adjustment in log2 space: w * log2(u_exact / tf) */
                                bf_tf_adj[k] = w * log2(u_exact / tf);
                            }
                        }
                    }

                    if (mk < 1e-10) mk = 1e-10;
                    if (uk < 1e-10) uk = 1e-10;

                    bf_vals[k] = log2(mk / uk) + bf_tf_adj[k];
                    total_log2_bf += bf_vals[k];
                }

                /* match_probability from Bayes factor and lambda */
                double bf_prod = pow(2.0, total_log2_bf);
                double p = (lambda * bf_prod) / (lambda * bf_prod + (1.0 - lambda));
                if (p < 1e-15) p = 1e-15;
                if (p > 1.0 - 1e-15) p = 1.0 - 1e-15;

                /* Output IDs or observation numbers */
                if (cfg.has_id_var) {
                    if (id_is_string && id_values) {
                        csv_write_field(pf, id_values[pair_a[i]]);
                        fputc(',', pf);
                        csv_write_field(pf, id_values[pair_b[i]]);
                    } else if (id_num_values) {
                        fprintf(pf, "%.0f,%.0f",
                            id_num_values[pair_a[i]], id_num_values[pair_b[i]]);
                    } else {
                        fprintf(pf, "%d,%d", pair_a[i] + 1, pair_b[i] + 1);
                    }
                } else {
                    fprintf(pf, "%d,%d", pair_a[i] + 1, pair_b[i] + 1);
                }
                fprintf(pf, ",%.6f,%.8f", total_log2_bf, p);
                for (int k = 0; k < cfg.n_comp; k++)
                    fprintf(pf, ",%d", comp_vec[i * cfg.n_comp + k]);
                for (int k = 0; k < cfg.n_comp; k++)
                    fprintf(pf, ",%.6f", bf_vals[k]);
                fprintf(pf, ",%d", match_key[i]);
                for (int k = 0; k < cfg.n_comp; k++) {
                    if (cfg.comp[k].tf_adjust)
                        fprintf(pf, ",%.8f,%.8f,%.6f",
                            tf_l_vals[k], tf_r_vals[k], bf_tf_adj[k]);
                }
                fprintf(pf, "\n");
            }
            fclose(pf);

            if (cfg.verbose) {
                char buf[256];
                snprintf(buf, sizeof(buf), "splink: pairwise output saved to %s\n", cfg.save_pairs);
                SF_display(buf);
            }
        }
    }

    /* ---- 11. Cluster matched pairs ---- */
    uf = uf_create(n);
    if (!uf) { rc = 909; goto cleanup; }

    {
        /* Determine effective cluster threshold */
        double ct = (cfg.cluster_threshold >= 0) ? cfg.cluster_threshold : cfg.threshold;

        if (cfg.cluster_method == 1) {
            /* Best-link clustering: each record links to at most one other */
            double *best_score = calloc((size_t)n, sizeof(double));
            int *best_partner = malloc((size_t)n * sizeof(int));
            if (!best_score || !best_partner) { free(best_score); free(best_partner); rc = 909; goto cleanup; }
            for (int bi = 0; bi < n; bi++) { best_score[bi] = -1e30; best_partner[bi] = -1; }

            for (long long i = 0; i < total_pairs; i++) {
                int above;
                if (cfg.use_weight_threshold) {
                    /* Compute match_weight for this pair */
                    double mw = 0.0;
                    for (int k = 0; k < cfg.n_comp; k++) {
                        int level = comp_vec[i * cfg.n_comp + k];
                        if (level == -1) {
                            int nm = (cfg.comp[k].null_mode >= 0) ? cfg.comp[k].null_mode : cfg.null_weight;
                            if (nm == NULL_NEUTRAL) continue;
                            else level = 0;
                        }
                        double mk = m_params[k][level], uk2 = u_params[k][level];
                        if (mk < 1e-10) mk = 1e-10;
                        if (uk2 < 1e-10) uk2 = 1e-10;
                        mw += log2(mk / uk2);
                    }
                    above = (mw >= cfg.weight_threshold);
                } else {
                    above = (p_match[i] >= ct);
                }
                if (above) {
                    n_matches++;
                    if (p_match[i] > best_score[pair_a[i]]) {
                        best_score[pair_a[i]] = p_match[i];
                        best_partner[pair_a[i]] = pair_b[i];
                    }
                    if (p_match[i] > best_score[pair_b[i]]) {
                        best_score[pair_b[i]] = p_match[i];
                        best_partner[pair_b[i]] = pair_a[i];
                    }
                }
            }
            /* Union only best links */
            for (int bi = 0; bi < n; bi++) {
                if (best_partner[bi] >= 0)
                    uf_union(uf, bi, best_partner[bi]);
            }
            free(best_score);
            free(best_partner);
        } else {
            /* Connected-components clustering (default) */
            for (long long i = 0; i < total_pairs; i++) {
                int above;
                if (cfg.use_weight_threshold) {
                    double mw = 0.0;
                    for (int k = 0; k < cfg.n_comp; k++) {
                        int level = comp_vec[i * cfg.n_comp + k];
                        if (level == -1) {
                            int nm = (cfg.comp[k].null_mode >= 0) ? cfg.comp[k].null_mode : cfg.null_weight;
                            if (nm == NULL_NEUTRAL) continue;
                            else level = 0;
                        }
                        double mk = m_params[k][level], uk2 = u_params[k][level];
                        if (mk < 1e-10) mk = 1e-10;
                        if (uk2 < 1e-10) uk2 = 1e-10;
                        mw += log2(mk / uk2);
                    }
                    above = (mw >= cfg.weight_threshold);
                } else {
                    above = (p_match[i] >= ct);
                }
                if (above) {
                    uf_union(uf, pair_a[i], pair_b[i]);
                    n_matches++;
                }
            }
        }
    }

    /* ---- 12. Assign sequential cluster IDs and write to Stata ---- */
    root_to_cid = calloc((size_t)n, sizeof(int));
    if (!root_to_cid) { rc = 909; goto cleanup; }

    {
        int next_cid = 1;
        for (int i = 0; i < n; i++) {
            int root = uf_find(uf, i);
            if (root_to_cid[root] == 0)
                root_to_cid[root] = next_cid++;
        }
        n_clusters = next_cid - 1;
    }

    for (int i = 0; i < n; i++) {
        int root = uf_find(uf, i);
        SF_vstore(out_var, i + 1, (double)root_to_cid[root]);
    }

    if (cfg.verbose) {
        char buf[256];
        snprintf(buf, sizeof(buf),
            "splink: %d matches, %d clusters\n", n_matches, n_clusters);
        SF_display(buf);
    }

    /* ---- 13. Write diagnostics ---- */
    {
        FILE *df = fopen(diag_path, "w");
        if (df) {
            fprintf(df, "n_pairs=%lld\n", (long long)total_pairs);
            fprintf(df, "n_matches=%d\n", n_matches);
            fprintf(df, "n_clusters=%d\n", n_clusters);
            fprintf(df, "lambda=%.8f\n", lambda);
            fprintf(df, "em_iterations=%d\n", em_iters);
            fprintf(df, "n_comp=%d\n", cfg.n_comp);
            fprintf(df, "mode=%d\n", cfg.mode);
            fprintf(df, "link_type=%s\n",
                cfg.link_type == LINK_ONLY ? "link_only" :
                cfg.link_type == LINK_AND_DEDUPE ? "link_and_dedupe" : "dedupe_only");

            for (int k = 0; k < cfg.n_comp; k++) {
                fprintf(df, "comp_%d_n_levels=%d\n", k, n_levels[k]);
                fprintf(df, "comp_%d_method=%d\n", k, cfg.comp[k].method);
                if (cfg.comp[k].var_name[0])
                    fprintf(df, "comp_%d_var_name=%s\n", k, cfg.comp[k].var_name);
                if (cfg.comp[k].tf_adjust && cfg.comp[k].var_name[0])
                    fprintf(df, "comp_%d_tf_column=%s\n", k, cfg.comp[k].var_name);
                fprintf(df, "comp_%d_tf_weight=%.4f\n", k, cfg.comp[k].tf_weight);
                for (int l = 0; l < n_levels[k]; l++) {
                    fprintf(df, "m_%d_%d=%.8f\n", k, l, m_params[k][l]);
                    fprintf(df, "u_%d_%d=%.8f\n", k, l, u_params[k][l]);
                }
            }
            /* EM iteration history */
            if (em_hist_n > 0) {
                fprintf(df, "em_history_n=%d\n", em_hist_n);
                for (int it = 0; it < em_hist_n; it++) {
                    fprintf(df, "em_hist_%d_lambda=%.8f\n", it, em_hist_lambda[it]);
                    fprintf(df, "em_hist_%d_maxchange=%.8f\n", it, em_hist_maxchange[it]);
                }
            }
            fclose(df);
        }
    }

    /* ---- 14. Cleanup ---- */
cleanup:
    if (block_keys_all) {
        for (int i = 0; i < cfg.n_block_rules * n; i++)
            if (block_keys_all[i]) free(block_keys_all[i]);
        free(block_keys_all);
    }
    if (str_comp) {
        for (int k = 0; k < cfg.n_comp; k++) {
            if (str_comp[k]) {
                for (int i = 0; i < n; i++)
                    if (str_comp[k][i]) free(str_comp[k][i]);
                free(str_comp[k]);
            }
        }
        free(str_comp);
    }
    if (num_comp) {
        for (int k = 0; k < cfg.n_comp; k++)
            if (num_comp[k]) free(num_comp[k]);
        free(num_comp);
    }
    free(link_source);
    free(sorted_idx);
    free(pair_a);
    free(pair_b);
    free(match_key);
    free(comp_vec);
    if (id_values) {
        for (int i = 0; i < n; i++)
            free(id_values[i]);
        free(id_values);
    }
    free(id_num_values);
    if (m_params) {
        for (int k = 0; k < cfg.n_comp; k++)
            if (m_params[k]) free(m_params[k]);
        free(m_params);
    }
    if (u_params) {
        for (int k = 0; k < cfg.n_comp; k++)
            if (u_params[k]) free(u_params[k]);
        free(u_params);
    }
    free(n_levels);
    free(p_match);
    uf_free(uf);
    free(root_to_cid);
    pairset_free(pairset);
    if (tf_record_freq) {
        for (int k = 0; k < cfg.n_comp; k++)
            free(tf_record_freq[k]); /* NULL-safe */
        free(tf_record_freq);
    }
    if (tf_tables) {
        for (int k = 0; k < cfg.n_comp; k++)
            tf_free(tf_tables[k]);
        free(tf_tables);
    }
    if (tf_pair_values) {
        for (long long i = 0; i < total_pairs; i++) {
            if (tf_pair_values[i]) {
                /* Free strdup'd numeric TF values (string ones are borrowed) */
                for (int k = 0; k < cfg.n_comp; k++) {
                    if (tf_pair_values[i][k] && !cfg.comp[k].is_string) {
                        free(tf_pair_values[i][k]);
                    }
                }
                free(tf_pair_values[i]);
            }
        }
        free(tf_pair_values);
    }

    return rc;
}
