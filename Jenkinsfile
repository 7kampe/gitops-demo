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
             
