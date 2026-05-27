# CI/CD Pipeline

This document covers the pipeline stages, how the final version works, the errors encountered during development, and the specific changes made to fix them.

---

## Pipeline Overview

The pipeline is defined in `.github/workflows/pipeline.yml` and is triggered on every push and pull request to `main`.

```
push / pull_request to main
        │
        ▼
   ┌─────────┐
   │  Lint   │  ← runs on all branches
   └────┬────┘
        ▼
   ┌─────────┐
   │  Test   │  ← runs on all branches
   └────┬────┘
        ▼
   ┌───────────────┐
   │ Security Scan │  ← runs on all branches
   └───────┬───────┘
           ▼
   ┌────────────────────────┐
   │ Build, Push & Deploy   │  ← main branch ONLY
   └────────────────────────┘
```

---

## Pipeline Stages

### 1. Lint
Runs `flake8` against the `app/` directory with a max line length of 100. Fails immediately if any violations are found, preventing bad code from advancing further in the pipeline.

```yaml
- run: pip install flake8
- run: flake8 app/ --max-line-length=100
```

### 2. Unit Tests
Installs dependencies from `requirements.txt` and runs `pytest`. Any failing test blocks the rest of the pipeline.

```yaml
- run: pip install -r requirements.txt
- run: pytest app/ -v
```

### 3. Security Scan
Uses [Trivy](https://github.com/aquasecurity/trivy) to scan the filesystem for known vulnerabilities. The pipeline fails if any `CRITICAL` or `HIGH` severity issues are found.

```yaml
- uses: aquasecurity/trivy-action@master
  with:
    scan-type: fs
    scan-ref: .
    severity: CRITICAL,HIGH
    exit-code: 1
```

### 4. Build, Push & Deploy *(main only)*
This is a single consolidated job that:
1. Authenticates to AWS using stored GitHub secrets
2. Logs into Amazon ECR
3. Builds the Docker image tagged with the commit SHA
4. Pushes the image to ECR
5. Downloads the current live task definition from AWS
6. Renders a new task definition with the updated image URI
7. Deploys to ECS Fargate and waits for the service to stabilize

```yaml
if: github.ref == 'refs/heads/main'
```

The `if:` condition on the job ensures this step only runs on pushes to `main`, never on pull requests.

---

## Errors Encountered and Fixes

### Error: `Input required and not supplied: image`

```
Run aws-actions/amazon-ecs-render-task-definition@v1
Error: Input required and not supplied: image
```

This was the main recurring error. It occurred because `amazon-ecs-render-task-definition` received an empty string for the `image` input. There were multiple root causes, addressed one by one.

---

#### Fix 1 — Merged `build-and-push` and `deploy` into a single job

**The problem:** The original pipeline had two separate jobs: `build-and-push` and `deploy`. The `deploy` job referenced the image URI using cross-job outputs:

```yaml
image: ${{ needs.build-and-push.outputs.image }}
```

Cross-job outputs only exist if the job that produced them actually ran and wrote to `$GITHUB_OUTPUT`. Since `build-and-push` had `if: github.ref == 'refs/heads/main'` but `deploy` had no such guard, the pipeline on a pull request would:

1. Skip `build-and-push` (guarded by the `if:`)
2. Run `deploy` anyway
3. Try to read `needs.build-and-push.outputs.image` — which is empty because the job never ran
4. Pass that empty string to `amazon-ecs-render-task-definition` → error

Even on `main` where both jobs ran, cross-job outputs have edge cases and are fragile wiring that can silently break.

**The fix:** Collapse both jobs into one. The image URI becomes a plain shell variable passed between steps in the same job — no output wiring at all.

```yaml
# Before — fragile cross-job output
jobs:
  build-and-push:
    outputs:
      image: ${{ steps.build-image.outputs.image }}
    ...
  deploy:
    needs: build-and-push
    steps:
      - uses: aws-actions/amazon-ecs-render-task-definition@v1
        with:
          image: ${{ needs.build-and-push.outputs.image }}  # empty on PRs

# After — single job, shell variable, always set
jobs:
  deploy:
    if: github.ref == 'refs/heads/main'
    steps:
      - name: Build, tag, and push image
        id: build-image
        run: |
          IMAGE_URI=$ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG
          docker build -t "$IMAGE_URI" .
          docker push "$IMAGE_URI"
          echo "image=$IMAGE_URI" >> "$GITHUB_OUTPUT"

      - uses: aws-actions/amazon-ecs-render-task-definition@v1
        with:
          image: ${{ steps.build-image.outputs.image }}  # same job — always set
```

---

#### Fix 2 — Added the `if:` guard to the deploy job

**The problem:** The `build-and-push` job had `if: github.ref == 'refs/heads/main'` but the `deploy` job did not. This meant on pull requests, `deploy` would attempt to run with no image available.

**The fix:** After merging the jobs, a single `if:` guard on the combined job covers both build and deploy together — there's no way for one half to run without the other.

---

#### Fix 3 — Removed hardcoded task definition revision (`:1`)

**The problem:** The task definition was referenced as `fargate-cicd-demo-task:1` with the revision number hardcoded. Every pipeline run registers a new ECS task definition revision (`:2`, `:3`, etc.). With `:1` hardcoded, every deploy would:

1. Download revision 1 — the original, oldest definition
2. Inject the new image into it
3. Deploy that, discarding any configuration changes made since revision 1

**The fix:** Remove the revision suffix entirely. The AWS CLI fetches the currently active revision when no number is specified.

```bash
# Before
aws ecs describe-task-definition --task-definition fargate-cicd-demo-task:1

# After
aws ecs describe-task-definition --task-definition fargate-cicd-demo-task
```

---

#### Fix 4 — Bumped `amazon-ecs-deploy-task-definition` from `@v1` to `@v2`

**The problem:** `@v1` is deprecated by AWS. It still runs but AWS has stopped patching it. GitHub Actions runner environments periodically update their Node.js version, which can silently break deprecated actions.

**The fix:** One-word change to `@v2`, the actively maintained version that AWS's own documentation points to.

```yaml
# Before
uses: aws-actions/amazon-ecs-deploy-task-definition@v1

# After
uses: aws-actions/amazon-ecs-deploy-task-definition@v2
```

---

#### Fix 5 — Removed debug `echo` steps left over from troubleshooting

**The problem:** During debugging, several `echo` steps were added to the pipeline to print diagnostic information:
- `Debug ECR login`
- `Debug repo secret`
- `Debug build command`
- `Debug image output`
- `Debug incoming image`

These were never removed. While harmless functionally, they printed the ECR registry URL, repository name, and full image URI into public GitHub Actions logs — unnecessary exposure of infrastructure details.

**The fix:** All debug steps removed from the final pipeline.

---

## Key Takeaway

The core insight from all of these fixes:

> `steps.X.outputs.Y` within one job is always reliable — it's written and read in the same process on the same runner. `needs.X.outputs.Y` across jobs only works if job X ran, completed successfully, and wrote the output — which it won't do when guarded by an `if:` condition that the dependent job doesn't share.

The single-job architecture eliminates an entire class of pipeline failures.
