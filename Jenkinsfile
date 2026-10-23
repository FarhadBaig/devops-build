
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

                    withCredentials([
                        usernamePassword(
                            credentialsId: 'dockerhub-creds',
                            usernameVariable: 'DOCKERHUB_USER',
                            passwordVariable: 'DOCKERHUB_TOKEN'
                        )
                    ]) {
                        sh """
                            set -eu
                            trap 'docker logout >/dev/null 2>&1 || true' EXIT

                            printf '%s' "\$DOCKERHUB_TOKEN" |
                                docker login --username "\$DOCKERHUB_USER" --password-stdin

                            docker build --tag '${imageRepo}:${imageTag}' .
                            docker push '${imageRepo}:${imageTag}'

                            echo "Published ${imageRepo}:${imageTag}"
                        """
                    }

                    if (env.BRANCH_NAME == 'master') {
                        sh """
                            set -eu

                            IMAGE='${imageRepo}:${imageTag}'
                            BACKUP_IMAGE=\$(docker inspect --format='{{.Config.Image}}' prod-web)

                            echo "Deploying \$IMAGE"
                            echo "Previous image: \$BACKUP_IMAGE"

                            docker rm -f prod-web

                            docker run -d \
                                --name prod-web \
                                --restart unless-stopped \
                                -p 8081:80 \
                                "\$IMAGE"

                            if ! curl --fail --silent --show-error \
                                --retry 10 --retry-delay 2 --retry-connrefused \
                                http://127.0.0.1:8081/health; then

                                echo "Health check failed. Rolling back."

                                docker rm -f prod-web || true

                                docker run -d \
                                    --name prod-web \
                                    --restart unless-stopped \
                                    -p 8081:80 \
                                    "\$BACKUP_IMAGE"

                                exit 1
                            fi

                            echo
                            echo "Production deployment successful"
                            docker ps --filter name=prod-web
                        """
                    }
                }
            }
        }
    }
}
