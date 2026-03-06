{smcl}
{* *! version 4.2.0  28feb2026}{...}
{viewerjumpto "Syntax" "splink##syntax"}{...}
{viewerjumpto "Description" "splink##description"}{...}
{viewerjumpto "Options" "splink##options"}{...}
{viewerjumpto "Comparison methods" "splink##compmethods"}{...}
{viewerjumpto "Training pipeline" "splink##training"}{...}
{viewerjumpto "Examples" "splink##examples"}{...}
{viewerjumpto "Stored results" "splink##results"}{...}
{viewerjumpto "Algorithm" "splink##algorithm"}{...}
{viewerjumpto "Composition (And/Or/Not)" "splink##composition"}{...}
{viewerjumpto "Scoring new records" "splink##newrecords"}{...}
{viewerjumpto "Python compatibility" "splink##compat"}{...}

{title:Title}

{phang}
{bf:splink} {hline 2} Probabilistic record linkage using the Fellegi-Sunter model

{marker syntax}{...}
{title:Syntax}

{p 8 17 2}
{cmdab:splink}
[{it:subcommand}]
{it:compvars}
{ifin}
{cmd:,} {opt gen:erate(newvar)} {opt block:var(varlist)}|{opt blockr:ules(string)} [{it:options}]

{pstd}
Subcommands: {bf:train}, {bf:predict} (or none for legacy mode)

{synoptset 30 tabbed}{...}
{synopthdr}
{synoptline}
{syntab:Required}
{synopt:{opt gen:erate(newvar)}}name of cluster ID variable to create{p_end}
{synopt:{opt block:var(varlist)}}1st blocking rule{p_end}
{synopt:{opt blockr:ules(string)}}semicolon-separated blocking rules (alternative to blockvar){p_end}

{syntab:Additional blocking rules (OR logic)}
{synopt:{opt block2(varlist)}}2nd blocking rule{p_end}
{synopt:{opt block3(varlist)}}3rd blocking rule{p_end}
{synopt:{opt block4(varlist)}}4th blocking rule{p_end}

{syntab:Comparison}
{synopt:{opt compm:ethod(string)}}comparison method per variable; see {help splink##compmethods:methods}{p_end}
{synopt:{opt compl:evels(string)}}thresholds per variable, pipe-separated{p_end}
{synopt:{opt comp:are(string)}}extended comparison spec with multi-column support{p_end}

{syntab:Term frequency}
{synopt:{opt tfa:djust(varlist)}}variables for term frequency adjustment{p_end}
{synopt:{opt tfmin(#)}}minimum TF u-value; default is {bf:0.001}{p_end}
{synopt:{opt tfw:eight(string)}}TF blending weight per var (0-1); default is {bf:1.0}{p_end}
{synopt:{opt tfs:ource(varlist)}}source vars for TF computation (instead of comp vars){p_end}
{synopt:{opt tfe:xactonly}}apply TF only to exact-match level{p_end}

{syntab:Model}
{synopt:{opt pr:ior(#)}}prior match probability; default is {bf:0.0001}{p_end}
{synopt:{opt thr:eshold(#)}}match probability threshold; default is {bf:0.85}{p_end}
{synopt:{opt clustert:hreshold(#)}}separate clustering threshold; default = threshold(){p_end}
{synopt:{opt weightt:hreshold(#)}}threshold on match weight (log2 BF) instead of probability{p_end}
{synopt:{opt max:iter(#)}}maximum EM iterations; default is {bf:25}{p_end}
{synopt:{opt maxb:locksize(#)}}max records per block; 0 = no limit (default){p_end}
{synopt:{opt nullw:eight(string)}}{bf:neutral} (default) or {bf:penalize}{p_end}
{synopt:{opt nullm:ode(string)}}per-var null mode: "neutral penalize ..."{p_end}
{synopt:{opt mprob(string)}}fixed m-probabilities per variable (pipe-separated){p_end}
{synopt:{opt uprob(string)}}fixed u-probabilities per variable (pipe-separated){p_end}
{synopt:{opt fixm:levels(string)}}per-level m fixing: "comp:level,level|..."{p_end}
{synopt:{opt fixu:levels(string)}}per-level u fixing: "comp:level,level|..."{p_end}
{synopt:{opt rec:all(#)}}recall for lambda estimation; default is {bf:1.0}{p_end}
{synopt:{opt fixl:ambda}}prevent EM from updating lambda{p_end}
{synopt:{opt emn:otf}}EM without term frequency adjustments{p_end}

{syntab:u-estimation}
{synopt:{opt ue:stimate}}estimate u via random sampling (Splink-style){p_end}
{synopt:{opt umaxp:airs(#)}}max random pairs for u estimation; default is {bf:1000000}{p_end}
{synopt:{opt us:eed(#)}}seed for random u estimation; default is {bf:42}{p_end}

{syntab:Linking}
{synopt:{opt link:var(varname)}}source indicator for cross-dataset linking{p_end}
{synopt:{opt linkt:ype(string)}}{bf:dedupe}, {bf:link}, or {bf:link_and_dedupe}{p_end}

{syntab:Model persistence}
{synopt:{opt savem:odel(filename)}}save trained model parameters to JSON{p_end}
{synopt:{opt loadm:odel(filename)}}load model parameters from JSON for scoring{p_end}

{syntab:Clustering}
{synopt:{opt clusterm:ethod(string)}}{bf:cc} (connected components, default) or {bf:bestlink}{p_end}
{synopt:{opt salt(#)}}blocking salting partitions (0 = disabled){p_end}
{synopt:{opt roundr:obin}}round-robin EM across blocking rules{p_end}
{synopt:{opt emtol(#)}}EM convergence tolerance; default is {bf:0.00001}{p_end}
{synopt:{opt timeu:nit(string)}}time unit for {bf:abs_time} method: {bf:seconds}, {bf:minutes}, {bf:hours}, {bf:days} (default){p_end}
{synopt:{opt ml:abel(varname)}}label column for supervised m-estimation{p_end}

{syntab:Output}
{synopt:{opt savep:airs(filename)}}save pairwise scores to CSV{p_end}
{synopt:{opt id(varname)}}unique ID variable (replaces obs numbers in output){p_end}

{syntab:Other}
{synopt:{opt replace}}replace existing variable{p_end}
{synopt:{opt v:erbose}}show progress and EM diagnostics{p_end}
{synoptline}

{marker description}{...}
{title:Description}

{pstd}
{cmd:splink} performs probabilistic record linkage (entity resolution) using
the Fellegi-Sunter model, closely matching the feature set of the Python
{browse "https://github.com/moj-analytical-services/splink":splink} package.

{pstd}
It identifies duplicate or matching records by comparing multiple fields using
configurable comparison functions (Jaro-Winkler, Levenshtein, Damerau-Levenshtein,
Jaccard, exact, numeric) with user-defined comparison levels, then estimates
match probabilities through Expectation-Maximization.

{pstd}
Key features:

{phang2}{bf:Configurable comparison levels:} Each variable can have a different number of
thresholds and comparison levels, giving fine-grained match weight estimation.{p_end}

{phang2}{bf:Multiple comparison functions:} Choose the best comparison method per variable:
fuzzy string matching, edit distance, bigram similarity, exact match, or numeric difference.{p_end}

{phang2}{bf:Multiple blocking rules (OR logic):} Up to 32 blocking rules combined with
OR logic using {opt blockrules()} or legacy {opt blockvar()}/{opt block2()}/{opt block3()}/{opt block4()}.{p_end}

{phang2}{bf:Term frequency adjustments:} Match weights are adjusted for value frequency:
matching on a rare value (e.g., "Xyzzynski") provides more evidence than matching
on a common value (e.g., "Smith").{p_end}

{phang2}{bf:Null handling:} Missing values receive a neutral Bayes factor (neither
for nor against matching) by default, instead of penalizing missingness.{p_end}

{phang2}{bf:Pairwise output:} Export all scored pairs with match weights, match
probabilities, per-field comparison levels, Bayes factors, TF details,
and match_key (blocking rule index) for auditing and threshold tuning.{p_end}

{phang2}{bf:Domain comparisons:} Specialized comparison functions for dates of birth,
email addresses, postcodes, and name swaps provide Python splink v4 parity.{p_end}

{phang2}{bf:Training pipeline:} Train/predict subcommands support the full
splink workflow. Save and load trained models as JSON for reproducibility.{p_end}

{phang2}{bf:Fuzzy TF:} Term frequency adjustments apply to both exact and fuzzy matches,
using max(tf_a, tf_b) for fuzzy pairs per the Python splink convention.{p_end}

{pstd}
The command supports three modes:

{phang2}{bf:Deduplication} (default): Find duplicate records within a single dataset.{p_end}

{phang2}{bf:Linking}: Link records across two datasets stacked with
{helpb append}. Specify {opt linkvar()} to indicate the source dataset.
Only cross-source pairs are compared.{p_end}

{phang2}{bf:Link and dedupe}: Compare all pairs regardless of source.
Specify {opt linktype(link_and_dedupe)}.{p_end}

{marker options}{...}
{title:Options}

{dlgtab:Required}

{phang}
{opt blockvar(varlist)} specifies one or more variables for the primary
blocking rule. Only records with identical blocking key values are compared.
Either {opt blockvar()} or {opt blockrules()} must be specified.

{phang}
{opt blockrules(string)} specifies blocking rules as semicolon-separated variable lists.
Supports up to 32 rules. Supports expression-based blocking with Stata functions:
{cmd:substr()}, {cmd:soundex()}, and {cmd:year()}.
Example: {cmd:blockrules(last_name ; dob_year city)}.
Example with expressions: {cmd:blockrules(substr(dob,1,4) ; soundex(last_name))}.

{phang}
{opt generate(newvar)} specifies the name of the cluster ID variable to create.
Records in the same cluster are predicted to represent the same entity.

{dlgtab:Additional blocking rules}

{phang}
{opt block2(varlist)}, {opt block3(varlist)}, {opt block4(varlist)} specify
additional blocking rules combined with OR logic. A candidate pair is generated
if it shares blocking key values under ANY rule. Duplicate pairs across rules
are automatically deduplicated.

{pstd}
Example: {cmd:block(last_name) block2(dob_year)} generates candidates sharing
{it:last_name} OR sharing {it:dob_year}.

{dlgtab:Comparison}

{phang}
{opt compmethod(string)} specifies one comparison method per comparison variable,
space-separated. If omitted, string variables default to {bf:jw} (Jaro-Winkler)
and numeric variables default to {bf:numeric}.
See {help splink##compmethods:comparison methods} for available methods.

{phang}
{opt complevels(string)} specifies comparison thresholds per variable using
pipe-separated groups. Within each group, thresholds are comma-separated
(highest to lowest for similarity methods, lowest to highest for distance methods).

{pstd}
Example: {cmd:complevels("0.95,0.88,0.70|1,2|0.80,0.60")} specifies 3 JW
thresholds for variable 1, 2 Levenshtein distance thresholds for variable 2,
and 2 Jaccard thresholds for variable 3.

{pstd}
If omitted, defaults depend on the comparison method:

{phang3}JW/Jaro: {bf:0.92, 0.80}{p_end}
{phang3}Levenshtein/DL: {bf:1, 2}{p_end}
{phang3}Jaccard: {bf:0.80, 0.60}{p_end}
{phang3}Exact: (none){p_end}
{phang3}Numeric: {bf:0, 1}{p_end}

{phang}
{opt compare(string)} specifies comparisons using an extended syntax that supports
multi-column comparisons and inline method/threshold specification. When specified,
it overrides {opt compmethod()} and {opt complevels()}.

{pstd}
Format: semicolons separate comparisons; commas separate the variable list from the
method and thresholds.

{pstd}
Syntax: {cmd:compare("}{it:vars}{cmd:,} {it:method}{cmd:(}{it:thresholds}{cmd:)} {cmd:;} {it:vars}{cmd:,} {it:method}{cmd:")}

{pstd}
Examples:

{phang3}{cmd:compare("first_name, jw(0.92,0.80) ; last_name, jw(0.95,0.88)")}{p_end}
{phang3}Single-column comparisons with different thresholds per variable.{p_end}

{phang3}{cmd:compare("first_name last_name, namesw")}{p_end}
{phang3}Multi-column nameswap: detects transposed first/last names.{p_end}

{phang3}{cmd:compare("lat lon, distance_km(1,10,50)")}{p_end}
{phang3}Haversine distance: levels at 1km, 10km, and 50km thresholds.{p_end}

{pstd}
For multi-column comparisons, input variables are concatenated into a single
tab-separated string variable automatically. The comparison method then parses
the combined value.

{pstd}
{bf:Custom comparisons:} Python splink supports SQL CASE-WHEN expressions for
custom comparisons. This is not feasible in C. Instead, precompute a variable
in Stata containing integer comparison levels (0 = else, higher = better match),
then pass it with {cmd:compmethod(custom)}. Example:

{phang3}{cmd:. gen int my_level = cond(var_a == var_b, 2, cond(abs(var_a - var_b) < 10, 1, 0))}{p_end}
{phang3}{cmd:. splink my_level other_var, block(city) gen(cid) compmethod(custom jw)}{p_end}

{dlgtab:Term frequency}

{phang}
{opt tfadjust(varlist)} specifies comparison variables for which term frequency
adjustments should be applied. For exact-match pairs on these variables, the
u-probability is replaced with the matched value's frequency, giving less
weight to common values.

{phang}
{opt tfmin(#)} specifies the minimum u-value after term frequency adjustment,
preventing extreme weights from very rare values. Default is {bf:0.001}.

{dlgtab:Model}

{phang}
{opt prior(#)} specifies the prior probability that two random records match
(0 to 1, exclusive). Default is {bf:0.0001}. For small datasets, this is
automatically raised to ensure the EM algorithm can converge.

{phang}
{opt threshold(#)} specifies the match probability threshold (0 to 1, inclusive of 1).
Pairs above this threshold are classified as matches. Default is {bf:0.85}.
Use {opt threshold(1.0)} for deterministic linking (exact-match-only).

{phang}
{opt maxiter(#)} specifies the maximum number of EM iterations. Default is
{bf:25}. The algorithm may converge earlier.

{phang}
{opt maxblocksize(#)} specifies the maximum number of records per block.
Blocks exceeding this limit are truncated with a warning. Default is {bf:5000}
(set in the .ado wrapper; the C plugin default is 0/no limit).
Set to {bf:0} for no limit (all records in the block are used, which may
be very slow for large blocks).

{phang}
{opt mprob(string)} specifies fixed m-probabilities per comparison variable.
Probabilities are pipe-separated per variable, comma-separated per level within
each variable. Level order is: else, fuzzy1 (lowest quality), ..., fuzzyN
(highest quality), exact. Null is handled separately via {opt nullweight()}
and should NOT appear in mprob()/uprob().
When specified, EM does not update the m-probabilities for that variable.

{pstd}
Example: {cmd:mprob("0.02,0.08,0.15,0.75|0.05,0.10,0.85")} fixes
m-probabilities for variables 1 (4 levels: else=0.02, fuzzy1=0.08,
fuzzy2=0.15, exact=0.75) and 2 (3 levels: else=0.05, fuzzy1=0.10,
exact=0.85). Leave a segment empty to allow EM estimation for that variable.

{phang}
{opt uprob(string)} specifies fixed u-probabilities, with the same format as
{opt mprob()}. Typically used with u-probabilities estimated from random
sampling ({opt uestimate}) or from a previous analysis.

{phang}
{opt uestimate} enables Splink-style u-probability estimation via random
(unblocked) pair sampling. Random pairs are overwhelmingly non-matches, giving
an unbiased estimate of u-probabilities. When enabled, u is fixed during
EM and only m-probabilities are estimated. This is the recommended approach
for medium-to-large datasets.

{phang}
{opt umaxpairs(#)} specifies the maximum number of random pairs to draw for
u-estimation. Default is {bf:1000000}. More pairs give more precise estimates.

{phang}
{opt useed(#)} specifies the random seed for u-estimation. Default is {bf:42}.

{phang}
{opt nullweight(string)} specifies how missing values are handled:

{phang3}{bf:neutral} (default): Missing values contribute a Bayes factor of 1
(neither for nor against matching).{p_end}

{phang3}{bf:penalize}: Missing values are treated as the lowest comparison level.{p_end}

{dlgtab:Linking}

{phang}
{opt linkvar(varname)} specifies a numeric variable indicating the source
dataset (e.g., 0 for dataset A, 1 for dataset B).

{phang}
{opt linktype(string)} specifies the linking mode:

{phang3}{bf:link} (default when {opt linkvar()} is specified): Only cross-source
pairs are compared.{p_end}

{phang3}{bf:dedupe}: Only within-source pairs are compared.{p_end}

{phang3}{bf:link_and_dedupe}: All pairs are compared regardless of source.{p_end}

{dlgtab:Output}

{phang}
{opt savepairs(filename)} saves all scored candidate pairs to a CSV file
containing: {it:unique_id_l}/{it:unique_id_r} (or {it:obs_a}/{it:obs_b}),
{it:match_weight}, {it:match_probability}, per-field {it:gamma_{name}},
per-field {it:bf_{name}}, {it:match_key} (blocking rule index), and for
TF-adjusted fields: {it:tf_{name}_l}, {it:tf_{name}_r}, {it:bf_tf_adj_{name}}.
When variable names are available, columns use named headers (e.g.,
{it:gamma_last_name}) instead of numeric indices. Use {opt id(varname)} to
output unique record IDs instead of observation numbers.

{dlgtab:Other}

{phang}
{opt replace} permits {cmd:splink} to overwrite an existing variable specified
in {opt generate()}.

{phang}
{opt verbose} displays progress information including blocking statistics,
EM iteration details, and adaptive prior adjustments.

{marker compmethods}{...}
{title:Comparison methods}

{pstd}
Available comparison methods for {opt compmethod()}:

{p2colset 5 24 26 2}{...}
{p2col:{bf:Method}}Description{p_end}
{p2line}
{p2col:{bf:jw}}Jaro-Winkler similarity (0-1, higher = more similar). Best for
short names and identifiers. Default for string variables.{p_end}
{p2col:{bf:jaro}}Jaro similarity (0-1). Like JW without the common-prefix boost.{p_end}
{p2col:{bf:lev}}Levenshtein edit distance (0+, lower = more similar). Counts
insertions, deletions, substitutions.{p_end}
{p2col:{bf:dl}}Damerau-Levenshtein distance (0+). Like Levenshtein but also
counts transpositions of adjacent characters.{p_end}
{p2col:{bf:jaccard}}Jaccard similarity on character bigrams (0-1). Good for
longer strings and multi-word fields.{p_end}
{p2col:{bf:exact}}Binary exact match only (match or no match). No fuzzy thresholds.{p_end}
{p2col:{bf:numeric}}Numeric absolute difference. Default for numeric variables.
Thresholds are maximum allowed differences.{p_end}
{p2col:{bf:cosine}}Cosine similarity on character bigrams (0-1). Alternative to Jaccard.{p_end}
{p2col:{bf:pctdiff}}Percentage difference for numeric variables: |a-b|/max(|a|,|b|).{p_end}
{p2col:{bf:intersect}}Token intersection for space-delimited values. Levels by overlap count.{p_end}
{p2col:{bf:dob}}Date of birth comparison (YYYY-MM-DD strings). 6 levels: exact, DL<=1,
<=1 month, <=1 year, <=10 years, else.{p_end}
{p2col:{bf:email}}Email address comparison. Levels: exact, username-exact, JW-username,
domain-only, else.{p_end}
{p2col:{bf:postcode}}Postcode comparison. Levels: exact, sector, district, area, else.{p_end}
{p2col:{bf:nameswap}}Forename/surname comparison (requires two name fields via compare()). 6
levels: exact-normal, exact-swapped, JW>=t1-normal, JW>=t1-swapped, JW>=t2-either, else.{p_end}
{p2col:{bf:name}}Name with phonetic matching (Double Metaphone + Jaro-Winkler). 5 levels:
exact, JW>=0.92, JW>=0.88, JW>=0.70 or metaphone match, else.{p_end}
{p2col:{bf:abs_date}}Absolute date difference on Stata numeric dates.{p_end}
{p2col:{bf:abs_time}}Absolute time difference on Stata %tc datetime values. Thresholds
are in the unit specified by {opt timeunit()}: {bf:seconds}, {bf:minutes}, {bf:hours},
or {bf:days} (default). Useful for datetime fields stored as Stata %tc (milliseconds since
01jan1960 00:00:00).{p_end}
{p2col:{bf:distance_km}}Haversine distance in km from lat/lon pairs. Requires two numeric
variables via {opt compare()}. Thresholds are maximum distances in km.{p_end}
{p2col:{bf:custom}}User-precomputed gamma levels. The variable holds integer level values.
See {help splink##composition:composition}.{p_end}
{p2line}

{pstd}
For similarity methods ({bf:jw}, {bf:jaro}, {bf:jaccard}), thresholds are
minimum similarity values (highest first). For distance methods ({bf:lev},
{bf:dl}, {bf:numeric}), thresholds are maximum distance values (lowest first).

{marker examples}{...}
{title:Examples}

{pstd}{bf:Basic deduplication (backward compatible)}{p_end}
{phang2}{cmd:. splink first_name last_name dob city, block(last_name) gen(cluster_id)}{p_end}

{pstd}{bf:Multiple comparison methods}{p_end}
{phang2}{cmd:. splink first_name last_name dob_year, block(city) gen(cid)} ///
{p_end}
{phang2}{cmd:     compmethod(jw lev numeric) complevels("0.95,0.88|1,2|0,5")}{p_end}

{pstd}{bf:Custom thresholds with Jaccard}{p_end}
{phang2}{cmd:. splink full_name occupation, block(city) gen(cid)} ///
{p_end}
{phang2}{cmd:     compmethod(jaccard jw) complevels("0.70,0.50|0.92,0.80")}{p_end}

{pstd}{bf:Multiple blocking rules (OR logic)}{p_end}
{phang2}{cmd:. splink first_name last_name, block(state) block2(dob_year) gen(cid)}{p_end}

{pstd}{bf:Term frequency adjustment}{p_end}
{phang2}{cmd:. splink first_name last_name city, block(dob) gen(cid)} ///
{p_end}
{phang2}{cmd:     tfadjust(last_name) tfmin(0.001)}{p_end}

{pstd}{bf:Cross-dataset linking}{p_end}
{phang2}{cmd:. use dataset_a, clear}{p_end}
{phang2}{cmd:. append using dataset_b, generate(source)}{p_end}
{phang2}{cmd:. splink first_name last_name dob, block(last_name) gen(entity_id) linkvar(source)}{p_end}

{pstd}{bf:Semicolon-separated blocking rules}{p_end}
{phang2}{cmd:. splink first_name last_name, blockrules(last_name ; dob_year city ; first_name dob) gen(cid)}{p_end}

{pstd}{bf:Training pipeline (train, save, score)}{p_end}
{phang2}{cmd:. splink train first_name last_name dob, block(city) gen(cid) savemodel(model.json)}{p_end}
{phang2}{cmd:. splink first_name last_name dob, block(city) gen(cid) loadmodel(model.json)}{p_end}

{pstd}{bf:Domain-specific comparisons}{p_end}
{phang2}{cmd:. splink first_name last_name email dob_str, block(city) gen(cid)} ///
{p_end}
{phang2}{cmd:     compmethod(jw jw email dob)}{p_end}

{pstd}{bf:Unique ID in pairwise output}{p_end}
{phang2}{cmd:. splink first_name last_name, block(city) gen(cid) id(person_id) savepairs(pairs.csv)}{p_end}

{pstd}{bf:Save pairwise scores for auditing}{p_end}
{phang2}{cmd:. splink first_name last_name dob, block(city) gen(cid)} ///
{p_end}
{phang2}{cmd:     savepairs("match_pairs.csv") verbose}{p_end}
{phang2}{cmd:. import delimited "match_pairs.csv", clear}{p_end}
{phang2}{cmd:. histogram match_probability, bin(50)}{p_end}

{pstd}{bf:Expression-based blocking}{p_end}
{phang2}{cmd:. splink first_name last_name, blockrules("substr(dob,1,4) ; soundex(last_name)") gen(cid)}{p_end}

{pstd}{bf:Multi-column nameswap via compare()}{p_end}
{phang2}{cmd:. splink first_name last_name, block(city) gen(cid)} ///
{p_end}
{phang2}{cmd:     compare("first_name last_name, namesw")}{p_end}

{pstd}{bf:Haversine distance via compare()}{p_end}
{phang2}{cmd:. splink name, block(state) gen(cid)} ///
{p_end}
{phang2}{cmd:     compare("lat lon, distance_km(1,10,50)")}{p_end}

{pstd}{bf:Mixed single- and multi-column compare()}{p_end}
{phang2}{cmd:. splink first_name last_name dob, block(city) gen(cid)} ///
{p_end}
{phang2}{cmd:     compare("first_name, jw(0.92,0.80) ; last_name, lev(1,2) ; dob, dob")}{p_end}

{pstd}{bf:Random u estimation (Splink-style, recommended for larger datasets)}{p_end}
{phang2}{cmd:. splink first_name last_name dob, block(city) gen(cid)} ///
{p_end}
{phang2}{cmd:     uestimate umaxpairs(500000) useed(12345)}{p_end}

{pstd}{bf:Fixed m/u probabilities}{p_end}
{phang2}{cmd:. splink first_name last_name, block(city) gen(cid)} ///
{p_end}
{phang2}{cmd:     mprob("0.05,0.85,0.05,0.03,0.02|0.05,0.90,0.03,0.02")}{p_end}

{pstd}{bf:Configuring the model}{p_end}
{phang2}{cmd:. splink first_name last_name dob, block(city) gen(cid)} ///
{p_end}
{phang2}{cmd:     prior(0.001) thr(0.90) nullweight(penalize) maxiter(50)}{p_end}

{pstd}{bf:Inspect results}{p_end}
{phang2}{cmd:. tab cluster_id}{p_end}
{phang2}{cmd:. duplicates tag cluster_id, gen(dup)}{p_end}
{phang2}{cmd:. list if dup > 0, sepby(cluster_id)}{p_end}

{marker results}{...}
{title:Stored results}

{pstd}
{cmd:splink} stores the following in {cmd:r()}:

{synoptset 25 tabbed}{...}
{p2col 5 25 29 2: Scalars}{p_end}
{synopt:{cmd:r(N)}}number of observations in sample{p_end}
{synopt:{cmd:r(n_pairs)}}number of candidate pairs evaluated{p_end}
{synopt:{cmd:r(n_matches)}}number of pairs classified as matches{p_end}
{synopt:{cmd:r(n_clusters)}}number of distinct clusters{p_end}
{synopt:{cmd:r(lambda)}}estimated match proportion (from EM){p_end}
{synopt:{cmd:r(em_iterations)}}number of EM iterations{p_end}
{synopt:{cmd:r(threshold)}}match probability threshold used{p_end}
{synopt:{cmd:r(prior)}}prior match probability used{p_end}

{p2col 5 25 29 2: Macros}{p_end}
{synopt:{cmd:r(compvars)}}comparison variables{p_end}
{synopt:{cmd:r(blockvar)}}primary blocking variables{p_end}
{synopt:{cmd:r(block2)}}2nd blocking rule variables (if specified){p_end}
{synopt:{cmd:r(block3)}}3rd blocking rule variables (if specified){p_end}
{synopt:{cmd:r(block4)}}4th blocking rule variables (if specified){p_end}
{synopt:{cmd:r(compmethod)}}comparison methods used{p_end}

{marker training}{...}
{title:Training Pipeline}

{pstd}
{cmd:splink} supports a multi-step training pipeline matching Python splink v4:

{phang2}{bf:splink train}: Estimates model parameters. Automatically runs random
u-estimation, then EM for m-probabilities. Estimates lambda deterministically.
Use {opt savemodel()} to persist the trained model.{p_end}

{phang2}{bf:splink predict} (or {opt loadmodel()}): Scores pairs using pre-trained
parameters. Skips EM entirely; uses fixed m/u probabilities from the loaded model.{p_end}

{phang2}{bf:splink} (no subcommand): Legacy mode. Runs the full pipeline in a single
command (blocking, comparison, EM, clustering).{p_end}

{pstd}
Model files are JSON matching the Python splink schema, containing
{it:probability_two_random_records_match} (lambda) and per-comparison
{it:m_probability}/{it:u_probability} arrays.

{pstd}
See also: {help splink_evaluate}, {help splink_truthspace}, {help splink_cluster_metrics},
{help splink_emhistory}, {help splink_graph_metrics}, {help splink_cluster_studio},
{help splink_blockstats}, {help splink_waterfall}, {help splink_muparam}, {help splink_compare}
for post-linkage evaluation and visualization tools.

{marker algorithm}{...}
{title:Algorithm}

{pstd}
{cmd:splink} implements the Fellegi-Sunter model of record linkage:

{phang2}1. {bf:Blocking}: Records are grouped by exact match on blocking variables.
Multiple blocking rules are combined with OR logic: a pair is a candidate if it
matches any rule. Pairs are deduplicated across rules using a hash set.{p_end}

{phang2}2. {bf:Comparison}: Each pair is compared on all comparison variables.
Each variable uses its configured comparison function and thresholds to produce
a comparison level (gamma). Gamma -1 is null (either value missing), 0 is else
(no match), ascending levels represent increasing similarity, and the maximum
level is exact match. This matches Python splink v4's gamma convention.{p_end}

{phang2}3. {bf:u-Estimation} (optional): When {opt uestimate} is specified, u-probabilities
are estimated from random (unblocked) pairs before EM. This gives unbiased
u-estimates since random pairs are overwhelmingly non-matches. u is then
fixed during EM (Splink's recommended workflow).{p_end}

{phang2}4. {bf:EM Estimation}: The Expectation-Maximization algorithm estimates
m-probabilities (P(comparison level | match)) and (unless pre-estimated)
u-probabilities (P(comparison level | non-match)) for each field and level,
plus lambda (the overall match proportion). The null level is excluded from
EM updates when {opt nullweight(neutral)} is set (default). For small datasets,
lambda is automatically raised from the prior to ensure convergence.{p_end}

{phang2}5. {bf:Term Frequency Adjustment}: For fields with TF adjustment enabled,
the u-probability for exact matches is replaced with the matched value's
frequency in the dataset. Common values contribute less evidence than rare values.{p_end}

{phang2}6. {bf:Scoring}: Each pair receives a match weight (log2 Bayes factor =
sum of per-field log2(m/u)) and a posterior match probability using Bayes'
rule with the estimated parameters and prior.{p_end}

{phang2}7. {bf:Clustering}: Pairs above the threshold are linked using
union-find, producing connected components as entity clusters.{p_end}

{marker remarks}{...}
{title:Remarks}

{pstd}
{bf:Unicode limitation:} String comparison functions (Jaro-Winkler, Levenshtein,
Damerau-Levenshtein, Jaccard) operate at the byte level. For ASCII text this is
correct, but multi-byte UTF-8 characters (accented names like "Müller",
CJK characters) may produce incorrect similarity scores. If your data contains
non-ASCII characters, consider normalizing to ASCII before comparison or using
{opt compmethod(exact)} for affected fields.

{marker composition}{...}
{title:Replicating Python Composition (And/Or/Not)}

{pstd}
Python splink's {bf:And()}, {bf:Or()}, {bf:Not()} compose comparison levels. Stata
achieves the same through the {bf:custom} comparison method, which passes a
user-precomputed gamma variable directly:

{phang2}{cmd:. * Python: And(jw("name") > 0.9, abs_diff("age") <= 2)}{p_end}
{phang2}{cmd:. * Stata equivalent:}{p_end}
{phang2}{cmd:. gen gamma_composite = (ustrsimilar(name_l, name_r) > 0.9) & (abs(age_l - age_r) <= 2)}{p_end}
{phang2}{cmd:. splink ..., compmethod(... custom) ...}{p_end}

{pstd}
The {bf:custom} method passes the variable's values directly as gamma levels
(0, 1, 2, ...) without any internal comparison. This enables arbitrary
compound conditions.

{marker newrecords}{...}
{title:Scoring New Records Against an Existing Model}

{pstd}
Python splink's {bf:find_matches_to_new_records()} scores new records against
an existing model. Stata achieves the same workflow:

{phang2}1. Train a model on original data and save it:{p_end}
{phang2}{cmd:. splink train name city dob, block(state) gen(cid) savemodel(model.json)}{p_end}

{phang2}2. Append new records and mark the source:{p_end}
{phang2}{cmd:. gen source = "original"}{p_end}
{phang2}{cmd:. append using newdata}{p_end}
{phang2}{cmd:. replace source = "new" if missing(source)}{p_end}

{phang2}3. Score using the saved model with link mode:{p_end}
{phang2}{cmd:. splink predict name city dob, block(state) gen(cid2) loadmodel(model.json) linkvar(source) linktype(link)}{p_end}

{pstd}
This generates pairs only between "original" and "new" records, scoring them
with the pre-trained parameters.

{marker postcodedist}{...}
{title:Postcode and Distance Comparisons}

{pstd}
Python splink's {bf:PostcodeComparison} with {bf:km_thresholds} integrates
geographic distance into postcode matching. Stata handles this through
separate comparison variables:

{phang2}{cmd:. * Use postcode as one comparison variable}{p_end}
{phang2}{cmd:. * Use distance_km as another with lat/lon input}{p_end}
{phang2}{cmd:. splink ..., compmethod(postcode distance_km) ...}{p_end}

{pstd}
The {bf:distance_km} method computes Haversine distances from tab-separated
lat/lon strings and applies user-specified thresholds.

{title:References}

{phang}
Fellegi, I.P. and A.B. Sunter. 1969. A theory for record linkage.
{it:Journal of the American Statistical Association} 64(328): 1183-1210.
{p_end}

{phang}
Splink: Free software for probabilistic record linkage at scale.
{browse "https://github.com/moj-analytical-services/splink"}
{p_end}

{marker compat}{...}
{title:Python splink Compatibility}

{pstd}
This Stata implementation targets feature parity with Python splink v4.0.15.
See {bf:FEATURE_PARITY.md} for a comprehensive comparison of every feature,
behavioral differences, and workarounds for features that require different
approaches in Stata.

{pstd}
Key differences: string comparisons operate at byte level (not Unicode),
cosine similarity uses string bigrams (not pre-computed arrays), and
composition (And/Or/Not) uses the {bf:custom} method with precomputed gammas.

{title:Author}

{pstd}
Generated with assistance from Claude Code.
{p_end}
