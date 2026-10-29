pipeline {
    agent {
        kubernetes {
            inheritFrom 'gitops-agent'
        }
    }

    stages {

        stage('Checkout') {
            steps {
                checkout([
                    $class: 'GitSCM',
                    branches: [[name: '*/main']],
                    userRemoteConfigs: [[
                        url: 'https://github.com/7kampe/gitops-demo.git',
                        credentialsId: 'github-push'
                    ]]
                ])

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

                        echo "=== Build application image ==="
                        podman build \
                          -t gitops-demo:test \
                          -f Containerfile \
                          .

                        aws ecr get-login-password --region eu-west-1 | \
                          podman login \
                          --username AWS \
                          --password-stdin \
                          211007024623.dkr.ecr.eu-west-1.amazonaws.com

                        podman tag gitops-demo:test \
                          211007024623.dkr.ecr.eu-west-1.amazonaws.com/gitops-demo:test

                        podman push \
                          211007024623.dkr.ecr.eu-west-1.amazonaws.com/gitops-demo:test
                    '''
                }
            }
        }

        stage('Update Helm values') {
            steps {
                container('tools') {
                    sh '''
                        #sed -i 's/tag: ".*"/tag: "test"/' nginx/values.yaml
                        grep -n "tag:" nginx/values.yaml
                        git diff -- nginx/values.yaml
                    '''
                }
            }
        }
        stage('Commit and Push') {
    steps {
        container('tools') {
            sh '''
                git config user.name "Jenkins"
                git config user.email "jenkins@localhost"

                git add nginx/values.yaml
                git commit -m "Update image tag to test"
                git push origin HEAD:main
            '''
        }
    }
}
    }
}
