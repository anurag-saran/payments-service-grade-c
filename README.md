# payments-service-grade-c

Sibling of **[payments-service](https://github.com/anurag-saran/payments-service)** for the
**grade C / human CAB** live demo. Same app sources, tests, Dockerfile, and deploy
manifests — used so upgrade-delta can show a **base-version** Lightwell bump that
headlines **C**, passes `fail-on: D`, then **waits** at `cab-decision` for a human
ConfigMap approval.

Not a production payments product. Package: `com.example.payments`.

## Why a separate repo?

| | payments-service | payments-service-notests | payments-service-grade-c | payments-service-grade-f |
|---|---|---|---|---|
| Hero | jackson drop-in → grade **B** | Empty tests → **REACHABILITY_ONLY** | json-path base bump → grade **C** | snakeyaml `1.30`→`1.33` → grade **F** |
| PipelineRun | `upgrade-delta-live-pr` | `upgrade-delta-live-pr-notests` | `upgrade-delta-live-pr-gradec` | `upgrade-delta-live-pr-gradef` |
| PVC | `upgrade-delta-live-reports` | `upgrade-delta-live-reports-notests` | `upgrade-delta-live-reports-gradec` | `upgrade-delta-live-reports-gradef` |
| Scorecard | Route `scorecard` | Route `scorecard-notests` | Route `scorecard-gradec` | Route `scorecard-gradef` |

Separate PVCs + viewers so concurrent demos never overwrite each other's reports.

## Build

JDK 17+.

```bash
mvn -B verify
# Equivalent (kept for pipeline scripts):
mvn -B -Pci-community verify
```

Produces a **fat / shaded** jar, CycloneDX `target/bom.json`, and JaCoCo under
`target/site/jacoco/`.

## Fast-lane demo (grade C / human CAB)

On `main`, keep **community** `json-path` `2.7.0`. Open a pom bump PR that adopts
Lightwell **`2.8.0.rhlw-00001` only** (do **not** bump snakeyaml — that headlines **F**):

```bash
./scripts/demo-live-cycle.sh start
# …watch upgrade-delta-live-pr-gradec-… on the cluster…
# When cab-decision waits:
oc create configmap upgrade-delta-cab-approved -n upgrade-delta-demo \
  --from-literal=approved=true
./scripts/demo-live-cycle.sh finish
```

Expect: headline **C** → grade-gate passes → `cab-decision` human wait → ConfigMap
approve → PR comment. Scorecard URL uses the **gradec** route host (see
`.tekton/pull-request-live.yaml`).

Details: upgrade-delta `docs/DEMO-LIVE-POM.md` § *Four live demos*.

## Layout

- `pom.xml` / `src/` — same call sites and tests as payments-service
- `coverage-map.json` — per-test coverage for fast-lane test selection
- `.upgrade-delta/` — vendored upgrade-delta live pipeline
- `.tekton/pull-request-live.yaml` — PaC trigger (`app-name: payments-service-grade-c`)
