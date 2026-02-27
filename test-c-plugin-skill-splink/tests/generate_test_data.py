#!/usr/bin/env python3
"""Generate test data for splink_stata validation.

Creates synthetic datasets with known duplicate structure, then runs
Python splink to produce reference linkage results for comparison.

Requirements (pin these versions):
    pip install splink==4.0.6 pandas==2.2.0 numpy==1.26.4
"""
import pandas as pd
import numpy as np
import os

OUTPUT_DIR = os.path.dirname(os.path.abspath(__file__))
SEED = 42


def generate_dedup_data(n_entities=500, dup_rate=0.3, noise_rate=0.1, seed=SEED):
    """Generate a dataset with known duplicates and controlled noise.

    Args:
        n_entities: Number of unique entities
        dup_rate: Fraction of entities that get a duplicate
        noise_rate: Probability of corrupting each field in a duplicate

    Returns:
        DataFrame with columns: record_id, first_name, last_name, dob_year,
        city, true_entity_id
    """
    rng = np.random.default_rng(seed)

    first_names = [
        "james", "mary", "robert", "patricia", "john", "jennifer", "michael",
        "linda", "david", "elizabeth", "william", "barbara", "richard", "susan",
        "joseph", "jessica", "thomas", "sarah", "charles", "karen", "daniel",
        "lisa", "matthew", "nancy", "anthony", "betty", "mark", "margaret",
        "donald", "sandra", "steven", "ashley", "paul", "dorothy", "andrew",
        "kimberly", "joshua", "emily", "kenneth", "donna", "kevin", "michelle",
        "brian", "carol", "george", "amanda", "timothy", "melissa", "ronald",
        "deborah"
    ]
    last_names = [
        "smith", "johnson", "williams", "brown", "jones", "garcia", "miller",
        "davis", "rodriguez", "martinez", "hernandez", "lopez", "gonzalez",
        "wilson", "anderson", "thomas", "taylor", "moore", "jackson", "martin",
        "lee", "perez", "thompson", "white", "harris", "sanchez", "clark",
        "ramirez", "lewis", "robinson", "walker", "young", "allen", "king",
        "wright", "scott", "torres", "nguyen", "hill", "flores"
    ]
    cities = [
        "new york", "los angeles", "chicago", "houston", "phoenix",
        "philadelphia", "san antonio", "san diego", "dallas", "san jose",
        "austin", "jacksonville", "fort worth", "columbus", "charlotte",
        "indianapolis", "san francisco", "seattle", "denver", "washington"
    ]

    def typo(name, rng):
        """Introduce a random character swap or deletion."""
        if len(name) < 3:
            return name
        chars = list(name)
        action = rng.integers(0, 3)
        if action == 0 and len(chars) > 3:
            # Swap adjacent characters
            pos = rng.integers(0, len(chars) - 1)
            chars[pos], chars[pos + 1] = chars[pos + 1], chars[pos]
        elif action == 1 and len(chars) > 3:
            # Delete a character
            pos = rng.integers(1, len(chars))
            chars.pop(pos)
        else:
            # Change a character
            pos = rng.integers(0, len(chars))
            chars[pos] = chr(rng.integers(ord('a'), ord('z') + 1))
        return ''.join(chars)

    records = []
    entity_id = 0

    for _ in range(n_entities):
        entity_id += 1
        fn = rng.choice(first_names)
        ln = rng.choice(last_names)
        dob = int(rng.integers(1950, 2005))
        ct = rng.choice(cities)

        records.append({
            'first_name': fn,
            'last_name': ln,
            'dob_year': dob,
            'city': ct,
            'true_entity_id': entity_id
        })

        # Create duplicate with noise
        if rng.random() < dup_rate:
            dup_fn = typo(fn, rng) if rng.random() < noise_rate else fn
            dup_ln = typo(ln, rng) if rng.random() < noise_rate else ln
            dup_dob = dob + int(rng.integers(-1, 2)) if rng.random() < noise_rate * 0.5 else dob
            dup_ct = ct if rng.random() > noise_rate * 0.3 else rng.choice(cities)

            records.append({
                'first_name': dup_fn,
                'last_name': dup_ln,
                'dob_year': dup_dob,
                'city': dup_ct,
                'true_entity_id': entity_id
            })

    df = pd.DataFrame(records)
    df['record_id'] = range(1, len(df) + 1)
    # Shuffle
    df = df.sample(frac=1, random_state=seed).reset_index(drop=True)
    df['record_id'] = range(1, len(df) + 1)

    return df


def generate_link_data(n_per_source=300, overlap=0.4, noise_rate=0.15, seed=SEED):
    """Generate two datasets with known overlap for linking.

    Returns:
        DataFrame with source column (0 or 1) and true_entity_id
    """
    rng = np.random.default_rng(seed + 100)

    first_names = ["james", "mary", "robert", "patricia", "john", "jennifer",
                   "michael", "linda", "david", "elizabeth"]
    last_names = ["smith", "johnson", "williams", "brown", "jones", "garcia",
                  "miller", "davis", "rodriguez", "martinez"]
    cities = ["new york", "los angeles", "chicago", "houston", "phoenix"]

    def typo(name, rng):
        if len(name) < 3:
            return name
        chars = list(name)
        pos = rng.integers(1, len(chars))
        chars[pos], chars[pos - 1] = chars[pos - 1], chars[pos]
        return ''.join(chars)

    # Create shared entities
    n_shared = int(n_per_source * overlap)
    entities = []
    for i in range(n_per_source):
        entities.append({
            'first_name': rng.choice(first_names),
            'last_name': rng.choice(last_names),
            'dob_year': int(rng.integers(1960, 2000)),
            'city': rng.choice(cities),
            'entity_id': i + 1,
        })

    records = []
    # Source A: all entities
    for e in entities:
        records.append({**e, 'source': 0, 'true_entity_id': e['entity_id']})

    # Source B: shared entities (with noise) + unique entities
    for i, e in enumerate(entities[:n_shared]):
        rec = {
            'first_name': typo(e['first_name'], rng) if rng.random() < noise_rate else e['first_name'],
            'last_name': e['last_name'],
            'dob_year': e['dob_year'],
            'city': e['city'],
            'source': 1,
            'true_entity_id': e['entity_id'],
        }
        records.append(rec)

    for i in range(n_per_source - n_shared):
        eid = n_per_source + i + 1
        records.append({
            'first_name': rng.choice(first_names),
            'last_name': rng.choice(last_names),
            'dob_year': int(rng.integers(1960, 2000)),
            'city': rng.choice(cities),
            'source': 1,
            'true_entity_id': eid,
        })

    df = pd.DataFrame(records)
    df['record_id'] = range(1, len(df) + 1)
    return df


def main():
    print("Generating deduplication test data...")
    dedup_df = generate_dedup_data()
    dedup_path = os.path.join(OUTPUT_DIR, 'test_dedup_data.csv')
    dedup_df.to_csv(dedup_path, index=False)
    print(f"  {len(dedup_df)} records, "
          f"{dedup_df['true_entity_id'].nunique()} true entities")
    print(f"  Saved to: {dedup_path}")

    n_dups = len(dedup_df) - dedup_df['true_entity_id'].nunique()
    print(f"  Known duplicates: {n_dups}")

    print("\nGenerating linking test data...")
    link_df = generate_link_data()
    link_path = os.path.join(OUTPUT_DIR, 'test_link_data.csv')
    link_df.to_csv(link_path, index=False)
    print(f"  {len(link_df)} records (source 0: {(link_df.source==0).sum()}, "
          f"source 1: {(link_df.source==1).sum()})")
    print(f"  Saved to: {link_path}")

    print("\nDone. Import into Stata with:")
    print('  import delimited "test_dedup_data.csv", clear')


if __name__ == '__main__':
    main()
