<!--
Please start the pull request title with the chart name in square brackets, e.g.
`[wordpress] Update default image`
-->

# Summary

Describe what this PR does and why. Keep it short and link related issues when applicable.

Example:

This PR fixes the startup crash in the `wordpress` chart by using the chart's service port from values instead of a hardcoded value. See issue #123.

---

## Checklist (required before merge)

- [ ] I have updated the `Chart.yaml` version for the affected chart(s) (bumped the `version` field).
- [ ] I have added an entry in the chart's `artifacthub.io/changes` annotation (in `Chart.yaml`) describing the change. Use one of the supported kinds: `added`, `changed`, `deprecated`, `removed`, `fixed`, `security`.
- [ ] I have appended an entry to the chart's `CHANGELOG.md` describing the change.
- [ ] I have run a quick install/upgrade smoke test where applicable.
- [ ] I have updated documentation or samples if necessary.

If your change only affects documentation or images and doesn't change chart behavior, please mention that and skip the Chart version bump if appropriate — but prefer bumping the chart version for clarity.

---

Additional notes:

- See Artifact Hub annotation docs for `artifacthub.io/changes`: https://artifacthub.io/docs/topics/annotations/helm/#supported-annotations
- When editing multiple charts, ensure each chart's `Chart.yaml` is updated, annotated, and its `CHANGELOG.md` appended.
