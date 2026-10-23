pipeline {
    agent any

    options {
        timestamps()
    }

    stages {
        stage('Validate Project') {
            steps {
                sh '''
                    set -eu
                    test -f Dockerfile
                    test -f nginx.conf
                    test -f deployment-proxy/nginx.conf
                    test -d build
                    docker --version
                    docker compose version
                    echo "Project validation successful"
                '''
            }
        }

        stage('Build and Push Image') {
            when {
                anyOf {
                    branch 'dev'
                    branch 'master'
                }
            }

            steps {
                script {
                    def imageRepo = env.BRANCH_NAME == 'dev'
                        ? 'farhadbaig/dev'
                        : 'farhadbaig/prod'

                    def imageTag = sh(
                        script: 'git rev-parse --short=7 HEAD',
                        returnStdout: true
                    ).trim()

                    env.BUILD_IMAGE = "${imageRepo}:${imageTag}"

                    withCredentials([
                        usernamePassword(
                            credentialsId: 'dockerhub-creds',
                            usernameVariable: 'DOCKERHUB_USER',
                            passwordVariable: 'DOCKERHUB_TOKEN'
                        )
                    ]) {
                        sh '''
                            set -eu
                            trap 'docker logout >/dev/null 2>&1 || true' EXIT

                            printf '%s' "$DOCKERHUB_TOKEN" |
                                docker login \
                                    --username "$DOCKERHUB_USER" \
                                    --password-stdin

                            docker build --tag "$BUILD_IMAGE" .
                            docker push "$BUILD_IMAGE"

                            echo "Published $BUILD_IMAGE"
                        '''
                    }
                }
            }
        }

        stage('Blue-Green Deploy to Test Proxy') {
            when {
                branch 'dev'
            }

            steps {
                sh '''
                    set -eu

                    PROXY=jenkins-proxy
                    BACKUP="/tmp/proxy-backup-${BUILD_NUMBER}.conf"
                    NEW_CONFIG="/tmp/proxy-new-${BUILD_NUMBER}.conf"

                    docker inspect "$PROXY" >/dev/null
                    docker exec "$PROXY" \
                        cat /etc/nginx/nginx.conf > "$BACKUP"

                    ACTIVE_PORT=$(sed -n \
                        's/.*server host.docker.internal:\\([0-9][0-9]*\\);.*/\\1/p' \
                        "$BACKUP" | head -n 1)

                    case "$ACTIVE_PORT" in
                        8082)
                            NEW_PORT=8085
                            NEW_CONTAINER=candidate-green
                            OLD_SLOT=candidate-green
                            ;;
                        8085)
                            NEW_PORT=8082
                            NEW_CONTAINER=candidate-blue
                            OLD_SLOT=candidate-blue
                            ;;
                        *)
                            echo "Unexpected proxy upstream: $ACTIVE_PORT"
                            exit 1
                            ;;
                    esac

                    echo "Current active port: $ACTIVE_PORT"
                    echo "New candidate: $NEW_CONTAINER on $NEW_PORT"

                    rollback_proxy() {
                        docker cp "$BACKUP" "$PROXY:/etc/nginx/nginx.conf"
                        docker exec "$PROXY" nginx -t
                        docker exec "$PROXY" nginx -s reload
                    }

                    # The selected slot is inactive, so it is safe to replace.
                    docker rm -f "$OLD_SLOT" >/dev/null 2>&1 || true

                    # Remove the legacy candidate only when port 8082 is inactive.
                    if [ "$NEW_PORT" = "8082" ]; then
                        docker rm -f candidate-web >/dev/null 2>&1 || true
                    fi

                    docker run -d \
                        --name "$NEW_CONTAINER" \
                        --restart unless-stopped \
                        -p "$NEW_PORT:80" \
                        "$BUILD_IMAGE"

                    if ! curl --fail --silent --show-error \
                        --retry 10 --retry-delay 2 --retry-connrefused \
                        "http://127.0.0.1:$NEW_PORT/health"; then
                        echo "Candidate health check failed; active proxy is unchanged"
                        docker rm -f "$NEW_CONTAINER" || true
                        exit 1
                    fi

                    echo "Candidate health check passed"

                    sed \
                        "s/server host.docker.internal:[0-9][0-9]*/server host.docker.internal:$NEW_PORT/" \
                        deployment-proxy/nginx.conf > "$NEW_CONFIG"

                    if ! docker cp "$NEW_CONFIG" \
                        "$PROXY:/etc/nginx/nginx.conf"; then
                        echo "Failed to install new proxy configuration; restoring previous route"
                        rollback_proxy || echo "WARNING: Automatic proxy rollback failed; manual recovery may be required"
                        docker rm -f "$NEW_CONTAINER" || true
                        exit 1
                    fi


                    if ! docker exec "$PROXY" nginx -t; then
                        echo "Proxy configuration invalid; restoring previous route"
                        rollback_proxy
                        docker rm -f "$NEW_CONTAINER" || true
                        exit 1
                    fi

                    if ! docker exec "$PROXY" nginx -s reload; then
                        echo "Proxy reload failed; restoring previous route"
                        rollback_proxy
                        docker rm -f "$NEW_CONTAINER" || true
                        exit 1
                    fi

                    if ! curl --fail --silent --show-error \
                        --retry 5 --retry-delay 2 \
                        http://127.0.0.1:8084/health; then
                        echo "Proxy health check failed; rolling back route"
                        rollback_proxy
                        docker rm -f "$NEW_CONTAINER" || true
                        exit 1
                    fi

                    if ! curl --fail --silent --show-error \
                        http://127.0.0.1:8084/ -o /dev/null; then
                        echo "Website check failed; rolling back route"
                        rollback_proxy
                        docker rm -f "$NEW_CONTAINER" || true
                        exit 1
                    fi

                    echo
                    echo "Blue-green deployment successful"
                    echo "Active upstream: $NEW_PORT"
                    docker ps --format 'table {{.Names}}\\t{{.Image}}\\t{{.Ports}}\\t{{.Status}}'
                '''
            }
        }
    }
}
