# Jenkins CI/CD and Docker Blue-Green Deployment Project

## 1. Project overview

This project implements a Jenkins-driven CI/CD pipeline for a web
application packaged as a Docker image. The pipeline validates the
project, builds and pushes an image to Docker Hub, and---on the `dev`
branch---deploys a candidate version using a blue-green strategy behind
an Nginx proxy.

**Current verified state:** the Jenkins pipeline succeeded for commit
`bc4fff35d7740a1697737fcf2f18faa37366ef0d` on branch `dev`. The active
test proxy routes to `candidate-green` on port `8085`. The production
application remains on port `8081` and is healthy.

**Known limitation:** external access to `http://3.110.156.148:8084/`
and `/health` from the Windows computer failed with a TCP connection
error. Local health checks pass, but external access has not been
demonstrated. This is documented as pending, not as a successful test.

## 2. Objectives

-   Validate project files before building.
-   Build a Docker image and tag it with the short Git commit SHA.
-   Push the image to Docker Hub.
-   Automatically deploy the `dev` branch to a candidate environment.
-   Use an Nginx proxy to switch test traffic between blue and green
    candidate slots.
-   Verify health endpoints after deployment.
-   Keep production on port `8081` unchanged during testing.
-   Preserve screenshots and command output as project evidence.

## 3. Environment and tools

  --------------------------------------------------------------------------------------
  Component                           Details
  ----------------------------------- --------------------------------------------------
  Workstation                         Windows with PowerShell

  Cloud                               AWS EC2, region `ap-south-1`

  EC2 instance                        `i-0ac9ed8b1a4784301` (`jenkins-server`)

  EC2 public IPv4                     `3.110.156.148` (verify in AWS before relying on
                                      it)

  EC2 private IPv4                    `172.31.3.151`

  Operating system                    Ubuntu 26.04.1 LTS

  Jenkins                             LTS `2.580.1`

  Java                                `21`

  Docker Engine                       `29.1.3`

  Docker Compose                      `2.40.3`

  Git repository                      `https://github.com/FarhadBaig/devops-build.git`

  Branches                            `dev`, `master`

  Jenkins job                         `devops-build-pipeline` (multibranch)

  Docker Hub Dev image repository     `farhadbaig/dev` (public)

  Docker Hub production image         `farhadbaig/prod` (private)
  repository                          

  Jenkins Docker Hub credential ID    `dockerhub-creds` (secret value must not be
                                      documented)
  --------------------------------------------------------------------------------------

Versions and public IP are recorded from the project session and may
change. Verify current values before operational use. Do not put Docker
Hub tokens or private keys in the documentation or Git.

## 4. Architecture

``` text
Windows workstation
   |
   | Git push (branch dev or master)
   v
GitHub repository: FarhadBaig/devops-build
   |
   v
Jenkins multibranch pipeline on EC2
   |
   +--> Validate project files
   |
   +--> Build Docker image tagged with short commit SHA
   |
   +--> Push image to Docker Hub
   |
   +--> If branch is dev: blue-green candidate deployment
              |
              +--> candidate-blue: host port 8082
              |
              +--> candidate-green: host port 8085
              |
              +--> jenkins-proxy: host port 8084
                         |
                         +--> active candidate slot
```

Production is separate from the test proxy:

``` text
prod-web --> host port 8081 --> production application
```

A legacy `candidate-web` container on port `8082` remains in the current
inventory alongside `candidate-green` on port `8085`. Do not remove it
as part of this documentation or troubleshooting task. The active proxy
currently points to port `8085`.

## 5. Container and port inventory

  -----------------------------------------------------------------------------------------
  Container / service            Host port       Container port Current observed state /
                                                                purpose
  ------------------- -------------------- -------------------- ---------------------------
  `prod-web`                        `8081`                 `80` Production; healthy; keep
                                                                unchanged

  `candidate-web`                   `8082`                 `80` Older candidate; healthy;
                                                                currently still running

  `test-proxy`                      `8083`                 `80` Additional test proxy;
                                                                running

  `jenkins-proxy`                   `8084`                 `80` Active test proxy; locally
                                                                healthy; external access
                                                                unresolved

  `candidate-green`                 `8085`                 `80` Active candidate, image
                                                                `farhadbaig/dev:bc4fff3`;
                                                                healthy
  -----------------------------------------------------------------------------------------

The Jenkinsfile is designed to alternate candidate slots between ports
`8082` and `8085`, updating the Nginx upstream after checking the new
candidate. Confirm the current upstream before assuming which slot is
active.

## 6. Repository structure

The tracked project files reported during the session include:

``` text
devops-build/
├── build/
├── Dockerfile
├── nginx.conf
├── docker-compose.yml
├── .dockerignore
├── .gitignore
├── scripts/
│   ├── build.sh
│   └── deploy.sh
├── Jenkinsfile
└── deployment-proxy/
    └── nginx.conf
```

Local backup files and screenshots are kept outside Git tracking. The
`.dockerignore` excludes `Screenshots/`. Avoid `git add .` if local
backups or evidence files are present; stage only the intended files.

## 7. Pipeline workflow

### Stage 1 --- Checkout

Jenkins checks out the selected branch from GitHub. The successful `dev`
run checked out commit:

``` text
bc4fff35d7740a1697737fcf2f18faa37366ef0d
```

### Stage 2 --- Validate project

The pipeline validates required project inputs, including:

-   `Dockerfile`
-   `nginx.conf`
-   `deployment-proxy/nginx.conf`
-   `build/` directory

The validation stage passed in the recorded successful run.

### Stage 3 --- Build and push image

The pipeline builds the Docker image and tags it using the short Git
commit SHA. For the successful `dev` build, the published tag was:

``` text
farhadbaig/dev:bc4fff3
```

Docker Hub login uses Jenkins credential ID `dockerhub-creds`. Keep the
credential secret in Jenkins Credentials; never print or commit the
token.

The recorded build emitted non-blocking warnings about Docker CLI
credential storage and the legacy Docker builder. These did not prevent
the image push.

### Stage 4 --- Blue-green deployment on `dev`

The pipeline:

1.  Reads the current proxy upstream port.
2.  Chooses the inactive candidate slot (port `8082` or `8085`).
3.  Removes/replaces only the inactive slot as defined by the
    Jenkinsfile.
4.  Starts the candidate container.
5.  Checks the candidate health endpoint.
6.  Updates the Nginx proxy configuration to the new slot.
7.  Copies the configuration into `jenkins-proxy`.
8.  Runs `nginx -t` before reloading Nginx.
9.  Reloads the proxy and checks `/health` and `/`.
10. Attempts rollback on the handled proxy configuration, reload, or
    health failures.

The successful run changed the active upstream from port `8082` to port
`8085`, deploying `candidate-green` from image `farhadbaig/dev:bc4fff3`.

### Branch behavior

-   `dev`: builds/pushes the Dev image and performs blue-green candidate
    deployment.
-   `master`: builds/pushes the production image to `farhadbaig/prod`;
    the described pipeline's blue-green deployment stage runs only on
    `dev`.

Do not assume that a successful image push to `master` proves a
production deployment unless a separate production deployment step is
verified.

## 8. Verification commands

Run these commands on the Ubuntu EC2 host. They are read-only checks and
do not restart or delete containers.

### Check proxy upstream

``` bash
sudo docker exec jenkins-proxy \
  grep 'server host.docker.internal' /etc/nginx/nginx.conf
```

Expected current output:

``` text
server host.docker.internal:8085;
```

### Check candidate health and image

``` bash
sudo docker inspect --format='{{.Name}}: {{.State.Health.Status}}' candidate-green
sudo docker inspect --format='{{.Config.Image}}' candidate-green
```

Expected:

``` text
/candidate-green: healthy
farhadbaig/dev:bc4fff3
```

### Check production health

``` bash
curl --fail --show-error http://127.0.0.1:8081/health
```

Expected:

``` text
healthy
```

### Check proxy health locally

``` bash
curl --fail --show-error http://127.0.0.1:8084/health
```

Expected:

``` text
healthy
```

This is a local test only; it does not prove external connectivity.

### Inspect listening ports

``` bash
sudo ss -lntp | grep -E ':8081|:8082|:8083|:8084|:8085'
```

### List containers

``` bash
sudo docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}\t{{.Status}}'
```

### Test external TCP from Windows PowerShell

``` powershell
Test-NetConnection 3.110.156.148 -Port 8084
```

The recorded result was a failed TCP connection. Do not document this as
passed.

## 9. External access status and troubleshooting record

### Observed facts

-   `jenkins-proxy` listens on `0.0.0.0:8084` and `[::]:8084` according
    to `ss`.
-   Local `curl http://127.0.0.1:8084/health` returned HTTP `200 OK` and
    `healthy`.
-   The candidate and production health checks returned `healthy`.
-   The EC2 security group was reported to have inbound TCP `8084`
    allowed from the user's current public IP `/32`.
-   The current public IP and the security group attachment were
    confirmed in the console.
-   The subnet network ACL has rule `100` allowing all traffic in both
    directions, followed by the default `* DENY`.
-   The subnet route table includes `172.31.0.0/16 -> local` and
    `0.0.0.0/0 -> igw-0b1ee03326bdea366`.
-   Windows `Test-NetConnection 3.110.156.148 -Port 8084` failed.
-   The packet-capture output (`tcpdump`) was not supplied, so it is not
    yet known whether the external SYN packets reached the instance.

### Conclusion

External test access remains unresolved. The evidence so far shows the
application and proxy are healthy locally, but the Windows client cannot
establish a TCP connection to port `8084`. Do not infer the exact cause
without further packet-level evidence. Potential next checks, when
troubleshooting resumes, include verifying the security-group rule and
current client public IP again, capturing packets on the EC2 host during
a connection attempt, and checking host firewall rules.

### Safety constraints

-   Keep production on host port `8081`.
-   Do not delete `prod-web`, `candidate-web`, or `candidate-green` to
    troubleshoot networking.
-   Do not open `8084` broadly to `0.0.0.0/0` as a casual diagnostic.
-   Do not change subnet routes or network ACLs without evidence.
-   Keep SSH private keys and Docker Hub credentials secret.

## 10. Screenshots and evidence checklist

The user reported saving the Jenkins success screenshot locally as:

``` text
Screenshots/22-blue-green-pipeline-success.png
```

Other locally reported screenshot files included:

``` text
Screenshots/14-jenkins-dev-build.png
Screenshots/15-...
Screenshots/16-...
Screenshots/17-...
Screenshots/18-...
Screenshots/19-...
Screenshots/20-jenkins-proxy-validated.png
```

The exact names for screenshots `15` through `19` were not recorded in
the available notes. Verify them in File Explorer rather than guessing.

Suggested evidence checklist:

-   [ ] GitHub repository and branch (`dev`)
-   [ ] Jenkins multibranch job and successful build
-   [ ] Jenkins console output showing validation and image push
-   [ ] Docker Hub Dev image tag `bc4fff3`
-   [ ] Blue-green deployment success in Jenkins
-   [ ] Proxy upstream points to `8085`
-   [ ] `candidate-green` health is `healthy`
-   [ ] Production health on port `8081` is `healthy`
-   [ ] Container inventory output
-   [ ] External connectivity failure recorded honestly as a pending
    item

Screenshots should remain local unless intentionally needed for a
report. `.dockerignore` excludes the `Screenshots/` directory from the
Docker build context; do not commit screenshots or backup files
accidentally.

## 11. Rollback and operational precautions

The Jenkinsfile contains guarded rollback behavior for handled failures
during proxy configuration, Nginx validation/reload, and proxy health
verification. Before manual intervention:

1.  Read the current upstream from `/etc/nginx/nginx.conf` inside
    `jenkins-proxy`.
2.  Verify which candidate is currently active.
3.  Preserve production `prod-web` on port `8081`.
4.  Do not remove the currently active candidate.
5.  Use the Jenkins pipeline's documented rollback path where applicable
    rather than improvising container deletion.

The current active upstream is `8085`, and the active candidate is
`candidate-green`.

## 12. Final status

### Completed and verified

-   Jenkins `dev` pipeline succeeded for commit `bc4fff3`.
-   Project validation passed.
-   Docker image was built and pushed to Docker Hub.
-   Blue-green deployment switched the test proxy to `candidate-green`
    on port `8085`.
-   Candidate health endpoint returned `healthy`.
-   Local test proxy health endpoint returned `healthy`.
-   Production health endpoint on port `8081` returned `healthy`.
-   Production was preserved during external access troubleshooting.

### Pending

-   External HTTP access to port `8084` from Windows.
-   Packet-level confirmation of whether the incoming TCP attempt
    reaches the EC2 instance.

**Final statement for a project submission:** The Jenkins CI/CD pipeline
and internal blue-green deployment have been implemented and verified.
The production container remains healthy on port `8081`. External access
to the test proxy on port `8084` is still under investigation and is not
claimed as successful.
