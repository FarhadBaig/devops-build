
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
                }
            }
        }
    }
}
