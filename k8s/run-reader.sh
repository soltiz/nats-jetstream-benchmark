#!/bin/bash -ue

# This script runs a PUSH reader job, that will accept 3 listening sessions, then stop

TEST_NUM="$(date +%s)"
: ${TEST_ID:=push-test-${TEST_NUM}}
: ${NB_READERS:=1}

: ${NB_SESSIONS:=1}
: ${TIMEOUT:=900s}
: ${FLOW_NAME:=myflow}
echo "Reader for flow ${FLOW_NAME}..."
JOB_NAME=push-reader-${TEST_ID}-${FLOW_NAME}

echo "Starting '${JOB_NAME}' job..."

kubectl apply -f - << EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
  labels:
    app: nats-reader
    app.kubernetes.io/name: nats-reader
spec:
  completions: ${NB_READERS}
  parallelism: ${NB_READERS}
  template:
    metadata:
      labels:
        app: nats-writer
        app.kubernetes.io/instance: nats-writer
    spec:
      restartPolicy: Never
      containers:
        - name: reader
          image: "kast-registry:30005/nats-tester:latest"
          imagePullPolicy: Always
          args:
            - reader
            - --json
            - -s
            - nats.default:4222
            - --flow
            - ${FLOW_NAME}
            - --max-listening-sessions
            - "${NB_SESSIONS}"
            - --test-id
            - "${TEST_ID}"
          env:
            - name: HOSTNAME
              valueFrom:
                fieldRef:
                  apiVersion: v1
                  fieldPath: metadata.name

EOF

{ 
	kubectl wait --for=condition=Ready pods -l job-name=${JOB_NAME} --timeout=${TIMEOUT}
	echo "Reader pods are running for job ${JOB_NAME}. following pods logs..."
	kubectl logs -l job-name=${JOB_NAME} --max-log-requests ${NB_READERS} --tail -1 -f
} &
LISTENER=$!

kubectl wait --for=condition=Complete job/${JOB_NAME} --timeout=${TIMEOUT}

echo "Reader job ${JOB_NAME} completed. Deleting it..."

wait $LISTENER

kubectl delete job "${JOB_NAME}"