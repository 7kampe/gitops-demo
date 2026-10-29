pipeline {
    agent {
        kubernetes {
            inheritFrom 'gitops-agent'
        }
    }

    options {
        skipDefaultCheckout(true)
    }

    environment {
        ECR_REGISTRY   = '211007024623.dkr.ecr.eu-west-1.amazonaws.com'
        ECR_REPOSITORY = 'gitops-demo'
        AWS_REGION     = 'eu-west-1'
    }

    stages {

        stage('Checkout') {
            steps {
                checkout([
                    $class: 'GitSCM',
                    branches: [[name: '*/main']],
                    userRemoteConfigs: [[
                        url: 'https://github.com/7kampe/gitops-demo.git',
                        credentialsId: 'git-push'
                    ]]
                ])

                script {
                    env.GIT_SHA = sh(
                        script: 'git rev-parse --short=7 HEAD',
                        returnStdout: true
                    ).trim()

                    echo "Git SHA: ${env.GIT_SHA}"
                }

                sh '''
                    git status
                    git log -1 --oneline
                '''
            }
        }

        stage('Verify') {
            steps {
                container('tools') {
                    sh '''
                        echo "=== Helm ==="
                        helm version

                        echo "=== Podman ==="
                        podman --version

                        echo "=== AWS CLI ==="
                        aws --version
                        aws sts get-caller-identity
                    '''
                }
            }
        }

        stage('Helm Lint') {
            steps {
                container('tools') {
                    sh '''
                        echo "=== Helm Lint ==="
                        helm lint nginx
                    '''
                }
            }
        }

        stage('Build Image') {
            steps {
                container('tools') {
                    sh '''
                        echo "=== Application Containerfile ==="
                        cat Containerfile

                        echo "=== Build image ${GIT_SHA} ==="

                        podman build \
                          -t ${ECR_REGISTRY}/${ECR_REPOSITORY}:${GIT_SHA} \
                          -f Containerfile \
                          .

                        echo "=== Login to ECR ==="

                        aws ecr get-login-password \
                          --region ${AWS_REGION} | \
                          podman login \
                          --username AWS \
                          --password-stdin \
                          ${ECR_REGISTRY}

                        echo "=== Push image ${GIT_SHA} ==="

                        podman push \
                          ${ECR_REGISTRY}/${ECR_REPOSITORY}:${GIT_SHA}
                    '''
                }
            }
        }

        stage('Update Helm values') {
            steps {
                container('tools') {
                    sh '''
                        echo "=== Current tag ==="
                        grep -n "tag:" nginx/values.yaml

                        echo "=== Updating tag to ${GIT_SHA} ==="

                        sed -i "s/tag: \\".*\\"/tag: \\"${GIT_SHA}\\"/" \
                          nginx/values.yaml

                        echo "=== New tag ==="
                        grep -n "tag:" nginx/values.yaml

                        echo "=== Git diff ==="
                        git diff -- nginx/values.yaml
                    '''
                }
            }
        }

        stage('Commit and Push') {
            steps {
                container('tools') {
                    withCredentials([
                        usernamePassword(
                            credentialsId: 'git-push',
                            usernameVariable: 'GIT_USERNAME',
                            passwordVariable: 'GIT_TOKEN'
                        )
                    ]) {
                        sh '''
                            set -eu

                            git config user.name "Jenkins"
                            git config user.email "jenkins@localhost"

                            git add nginx/values.yaml

                            if git diff --cached --quiet; then
                                echo "No changes to commit"
                                exit 0
                            fi

                            echo "=== Commit ==="

                            git commit \
                              -m "Update image tag to ${GIT_SHA}"

                            echo "=== Configure Git authentication ==="

                            ASKPASS_FILE="$(mktemp)"

                            cat > "${ASKPASS_FILE}" <<'EOF'
#!/bin/sh
case "$1" in
    *Username*)
        printf '%s\\n' "${GIT_USERNAME}"
        ;;
    *Password*)
        printf '%s\\n' "${GIT_TOKEN}"
        ;;
esac
EOF

                            chmod 700 "${ASKPASS_FILE}"

                            echo "=== Push to GitHub ==="

                            GIT_ASKPASS="${ASKPASS_FILE}" \
                            GIT_TERMINAL_PROMPT=0 \
                            git push origin HEAD:main

                            rm -f "${ASKPASS_FILE}"
                        '''
                    }
                }
            }
        }
    }
}
