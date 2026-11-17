# Sample Rollout Questions
for: the reviewer
context: Three sample questions to exercise every part of the input format.

## Q1 - S-GATE: Which gate guards the new `/uploads` routes?
Source: spec 5.2 (line 61)
What it is: The routes need a feature gate. The old gate reads every body into memory,
which is unsafe for large uploads.
Example: A 400 MB POST arrives while the feature is off.
- A (recommended): New streaming gate. Example: the POST gets 403 before any body is read.
- B: Reuse the old gate. Example: the body is buffered first.
- C: Patch the old gate for every caller.
Answer:
Decision:

## Q2 - S-NAME: May a deleted name be reused?
What it is: Steps pin a file by name and label.

A note line that is not a field becomes an extra paragraph.
- A: Yes, reusable.
- B (recommended): No, refuse while referenced.
Answer: Other: ask design first

## Q3 - S-CASE: Are names case-sensitive? <b>not html</b>
Spec: spec 3.1
What it is: One rule must hold in the resolver and the lock.
- A (recommended): Exact match.
- B: Case-insensitive.
Answer: B

## Note on scope
This is a plain note card, not a question.
