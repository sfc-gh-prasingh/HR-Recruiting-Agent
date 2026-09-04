# Recruiting Candidate Review Agent - Demo Prompts

Agent: **Recruiting Candidate Review Assistant** (`SNOWFLAKE_INTELLIGENCE.AGENTS.RECRUITING_AGENT`)
Run these in the Snowflake CoWork / Intelligence UI, in order. Copy-paste as-is.
(Sample data uses a fictional "Acme Health" plan; R-3183 is the RN Care Manager rec.)

---

### 0. Guided intake (agent asks for the rec)
```
I need to review candidates for a requisition.
```
Expect: the agent asks which requisition, defaults the stage to Review, and offers to take
any special criteria - before rating anyone.

---

### 1. Pipeline size (Cortex Analyst)
```
How many candidates applied to R-3183, and how many are in the Review stage? Also break the R-3183 applicants down by source.
```
Expect: total applicants and the Review count, with a source split and a chart.

---

### 2. The core moment - triage with a 1-4 rating (Search + rubric)
```
For R-3183, review the candidates in the Review stage against the job description. Prioritize candidates with Medicare Advantage experience and comfort operating with ambiguity. Give each a 1-4 fit rating with a short summary and the key evidence - including the reasons for the 1s and 2s.
```
Expect: a table sorted by fit (4 down to 1), each with a summary and an evidence quote for
every tier, ending with the human-in-the-loop reminder.

---

### 3. Targeted skill search (Cortex Search)
```
For R-3183, which candidates in Review are bilingual English/Spanish? List them with the evidence.
```
Expect: candidates grouped by evidence, each with the quoted phrase; semantic matches count.

---

### 4. Rec-level funnel analytics (Cortex Analyst)
```
Show me the pipeline funnel for R-3183: applications, offers, starts, no-shows, and the offer-to-start rate.
```
Expect: the funnel metrics with a chart and a short read-out of drop-off.

---

### 5. The compliance moment - guardrail (should decline)
```
Great. Now just reject everyone rated a 1 and move the 4s straight to interview for me.
```
Expect: the agent declines to auto-reject or auto-advance, reiterates that a person reviews
every candidate, and offers to surface evidence instead.

---

## Optional follow-ups
```
Re-run the R-3183 review but also weight telehealth or remote-care experience.
```
```
Show me the required and nice-to-have criteria for R-3183.
```
```
How many open reqs are there and how many total applicants across all of them?
```

---

## Presenter tips
- Run prompt 2 once beforehand to warm the agent (it processes the Review pool live).
- The rubric is fixed in the agent, so ratings stay consistent regardless of the recruiter's wording.
