# Quality Checklist

Architect-specific *self-assessment* methodology to use during the Validate phase. This complements (it does not duplicate) the deterministic gates:

- **Structural checks** are now covered by `scripts/validate_skill.py` (symlink to the shared substrate). Phase 4 invokes it deterministically — no need to re-check those items manually.
- **Audit rules J1–J29** live in `references/rules.md` (symlink). Treat them as a reference when validation surprises you; architect should already be constructing skills that pass them by default.

What this file adds on top: subjective rubrics and trigger-testing methodology that are useful while *building* a skill, before it ever reaches a reviewer.

---

## Description Quality (Score 1-5)

Rate each and target 4+ on all:

- [ ] **Specificity (1-5):** Does it describe a concrete capability?
- [ ] **Trigger clarity (1-5):** Would the agent know when to load this?
- [ ] **User language (1-5):** Does it use phrases a user would actually say?
- [ ] **Scope boundaries (1-5):** Is it clear what this skill does NOT do?
- [ ] **Pushiness (1-5):** Is it assertive enough to avoid undertriggering?

## Instruction Quality (Score 1-5)

- [ ] **Actionability (1-5):** Can the agent follow every step without ambiguity?
- [ ] **Specificity (1-5):** Are instructions concrete (not "validate properly")?
- [ ] **Examples (1-5):** Are there realistic input/output examples?
- [ ] **Error handling (1-5):** Are common failures addressed?
- [ ] **Progressive disclosure (1-5):** Is SKILL.md focused, with details in refs?
- [ ] **Composability (1-5):** Does it play well with other skills?

## Trigger Testing

### Should trigger (test 3-5 phrases)

1. [ ] "[Obvious request]" → triggers? Y/N
2. [ ] "[Paraphrased request]" → triggers? Y/N
3. [ ] "[Informal request]" → triggers? Y/N

### Should NOT trigger (test 3-5 phrases)

1. [ ] "[Unrelated task]" → stays silent? Y/N
2. [ ] "[Similar but different scope]" → stays silent? Y/N
3. [ ] "[Generic question]" → stays silent? Y/N

## Performance Targets

Aspirational benchmarks (adapt to your skill):

- [ ] Triggers on ≥90% of relevant queries
- [ ] Completes workflow without user correction
- [ ] Consistent results across separate sessions
- [ ] No failed tool/API calls per workflow
- [ ] Users don't need to prompt the agent about next steps

## Final Sign-Off

- [ ] User has reviewed the skill
- [ ] Validator and security sweep pass (see Phase 4)
- [ ] Test phrases produce expected behavior
- [ ] Skill is packaged and ready for upload
