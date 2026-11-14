## Validity, cost, invocation

| Fixture | Arm | valid | errors | contaminated | mean cost USD | mean wall s | mean turns | invoked typescript-dev | invoked (any) |
|---|---|---|---|---|---|---|---|---|---|
| F41 | before | 10 | 0 | 0 | 0.32 | 84 | 7.9 | 0/10 | nodejs-service-dev |
| F41 | after | 10 | 0 | 0 | 0.31 | 75 | 7.6 | 10/10 | typescript-dev |
| F42 | before | 10 | 0 | 0 | 0.36 | 96 | 5.0 | 0/10 | product-rd-workflow |
| F42 | after | 10 | 0 | 0 | 0.37 | 101 | 7.0 | 10/10 | product-rd-workflow, typescript-dev |
| F43 | before | 10 | 0 | 0 | 0.38 | 102 | 4.6 | 0/10 | — |
| F43 | after | 10 | 0 | 0 | 0.40 | 98 | 7.7 | 10/10 | typescript-dev |
| F44 | before | 10 | 0 | 0 | 0.31 | 78 | 7.2 | 0/10 | nodejs-service-dev, product-rd-workflow |
| F44 | after | 10 | 0 | 0 | 0.34 | 72 | 7.8 | 10/10 | typescript-dev |

Contamination hits: 0

## Rubric coverage (blinded judge)

| Fixture | before mean | after mean | delta | permutation p | judged before/after | W-flags before | W-flags after |
|---|---|---|---|---|---|---|---|
| F41 | 0.68 | 0.87 | +0.19 | 0.0016 | 10/10 | 0 | 0 |
| F42 | 0.77 | 0.91 | +0.14 | 0.0003 | 10/10 | 1 | 0 |
| F43 | 0.90 | 0.99 | +0.09 | 0.0002 | 10/10 | 0 | 0 |
| F44 | 0.78 | 0.93 | +0.15 | 0.0000 | 10/10 | 0 | 0 |

## Per item (met / partial / missed; W = answers showing the weakness)

| Fixture | Item | before | after |
|---|---|---|---|
| F41 | S1 | 10/0/0 | 10/0/0 |
| F41 | S2 | 10/0/0 | 10/0/0 |
| F41 | S3 | 0/0/10 | 7/0/3 |
| F41 | S4 | 0/8/2 | 3/7/0 |
| F41 | S5 | 10/0/0 | 10/0/0 |
| F41 | W1 | 0 | 0 |
| F41 | W2 | 0 | 0 |
| F41 | W3 | 0 | 0 |
| F42 | S1 | 10/0/0 | 10/0/0 |
| F42 | S2 | 10/0/0 | 10/0/0 |
| F42 | S3 | 9/1/0 | 10/0/0 |
| F42 | S4 | 1/8/1 | 10/0/0 |
| F42 | S5 | 4/5/1 | 9/1/0 |
| F42 | S6 | 0/10/0 | 0/10/0 |
| F42 | W1 | 0 | 0 |
| F42 | W2 | 1 | 0 |
| F42 | W3 | 0 | 0 |
| F43 | S1 | 10/0/0 | 10/0/0 |
| F43 | S2 | 10/0/0 | 10/0/0 |
| F43 | S3 | 0/10/0 | 9/1/0 |
| F43 | S4 | 10/0/0 | 10/0/0 |
| F43 | S5 | 10/0/0 | 10/0/0 |
| F43 | W1 | 0 | 0 |
| F43 | W2 | 0 | 0 |
| F43 | W3 | 0 | 0 |
| F44 | S1 | 10/0/0 | 10/0/0 |
| F44 | S2 | 10/0/0 | 10/0/0 |
| F44 | S3 | 0/10/0 | 5/5/0 |
| F44 | S4 | 0/10/0 | 8/2/0 |
| F44 | S5 | 8/2/0 | 10/0/0 |
| F44 | W1 | 0 | 0 |
| F44 | W2 | 0 | 0 |
| F44 | W3 | 0 | 0 |

## Judge-reported wrong facts (count of answers with ≥1)

- F41 before: 1/10
- F41 after: 4/10
- F42 before: 2/10
- F42 after: 5/10
- F43 before: 2/10
- F43 after: 1/10
- F44 before: 1/10
- F44 after: 2/10
