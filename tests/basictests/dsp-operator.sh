#!/bin/bash

source $TEST_DIR/common

MY_DIR=$(readlink -f `dirname "${BASH_SOURCE[0]}"`)

source ${MY_DIR}/../util
RESOURCEDIR="${MY_DIR}/../resources/dsp-operator"

os::test::junit::declare_suite_start "$MY_SCRIPT"


function verify_data_science_pipelines_operator_install() {
    header "Testing Data Science Pipelines operator installation"

    os::cmd::expect_success_and_text "oc get deployment -n openshift-operators openshift-pipelines-operator" "openshift-pipelines-operator"
    runningpods=($(oc get pods -n openshift-operators -l name=openshift-pipelines-operator --field-selector="status.phase=Running" -o jsonpath="{$.items[*].metadata.name}"))
    os::cmd::expect_success_and_text "echo ${#runningpods[@]}" "1"

    os::cmd::expect_success_and_text "oc get deployment -n ${ODHPROJECT} data-science-pipelines-operator-controller-manager" "data-science-pipelines-operator-controller-manager"
    runningpods=($(oc get pods -n ${ODHPROJECT} --field-selector="status.phase=Running" -o jsonpath="{$.items[*].metadata.name}"))
    os::cmd::expect_success_and_text "echo ${#runningpods[@]}" "3"
}

function create_and_verify_data_science_pipelines_resources() {
    header "Testing Data Science Pipelines installation with help of DSPO CR"

    os::cmd::expect_success "oc apply -f ${RESOURCEDIR}/test-dspo-cr.yaml"
    os::cmd::try_until_text "oc get crd dspipelines.dspipelines.opendatahub.io" "dspipelines.dspipelines.opendatahub.io" $odhdefaulttimeout $odhdefaultinterval
    os::cmd::try_until_text "oc get pods -l component=data-science-pipelines --field-selector='status.phase!=Running,status.phase!=Completed' -o jsonpath='{$.items[*].metadata.name}' | wc -w" "0" $odhdefaulttimeout $odhdefaultinterval
    running_pods=$(oc get pods -l component=data-science-pipelines --field-selector='status.phase=Running' -o jsonpath='{$.items[*].metadata.name}' | wc -w)
    os::cmd::expect_success "if [ "$running_pods" -gt "0" ]; then exit 0; else exit 1; fi"
}

function create_pipeline() {
    header "Creating a pipeline from data science pipelines stack"

    ROUTE=$(oc get route ds-pipeline-ui-sample --template={{.spec.host}})
    SA_TOKEN=$(oc whoami --show-token)

    PIPELINE_ID=$(curl -s -k -H "Authorization: Bearer ${SA_TOKEN}" -F "uploadfile=@${RESOURCEDIR}/test-pipeline-run.yaml" https://${ROUTE}/apis/v1beta1/pipelines/upload | jq -r .id)
    os::cmd::try_until_not_text "curl -s -k -H 'Authorization: Bearer ${SA_TOKEN}' https://${ROUTE}/apis/v1beta1/pipelines/${PIPELINE_ID} | jq" "null" $odhdefaulttimeout $odhdefaultinterval
}

function verify_pipeline_availabilty() {
    header "verify the pipelines exists"
    os::cmd::try_until_text "curl -s -k -H 'Authorization: Bearer ${SA_TOKEN}' https://${ROUTE}/apis/v1beta1/pipelines | jq '.total_size'" "1" $odhdefaulttimeout $odhdefaultinterval
}

function create_run() {
    header "Creating the run from uploaded pipeline"
    RUN_ID=$(curl -s -k -H "Authorization: Bearer ${SA_TOKEN}" -H "Content-Type: application/json"  -d "{\"name\":\"test-pipeline-run_run\", \"pipeline_spec\":{\"pipeline_id\":\"${PIPELINE_ID}\"}}" https://${ROUTE}/apis/v1beta1/runs | jq -r .run.id)
    os::cmd::try_until_not_text "curl -s -k -H 'Authorization: Bearer ${SA_TOKEN}' https://${ROUTE}/apis/v1beta1/runs/${RUN_ID} | jq '" "null" $odhdefaulttimeout $odhdefaultinterval
}

function verify_run_availabilty() {
    header "verify the run exists"
    os::cmd::try_until_text "curl -s -k -H 'Authorization: Bearer ${SA_TOKEN}' https://${ROUTE}/apis/v1beta1/runs | jq '.total_size'" "1" $odhdefaulttimeout $odhdefaultinterval
}

function check_run_status() {
    header "Checking run status"
    os::cmd::try_until_text "curl -s -k -H 'Authorization: Bearer ${SA_TOKEN}' https://${ROUTE}/apis/v1beta1/runs/${RUN_ID} | jq '.run.status'" "Completed" $odhdefaulttimeout $odhdefaultinterval
}

function delete_runs() {
    header "Deleting the runs"
    os::cmd::try_until_text "curl -s -k -H 'Authorization: Bearer ${SA_TOKEN}' -X DELETE https://${ROUTE}/apis/v1beta1/runs/${RUN_ID} | jq" "" $odhdefaulttimeout $odhdefaultinterval
    os::cmd::try_until_text "curl -s -k -H 'Authorization: Bearer ${SA_TOKEN}' https://${ROUTE}/apis/v1beta1/runs/${RUN_ID} | jq '.code'" "5" $odhdefaulttimeout $odhdefaultinterval
}

function delete_pipeline() {
    header "Deleting the pipeline"
    os::cmd::try_until_text "curl -s -k -H 'Authorization: Bearer ${SA_TOKEN}' -X DELETE https://${ROUTE}/apis/v1beta1/pipelines/${PIPELINE_ID} | jq" "" $odhdefaulttimeout $odhdefaultinterval
}


echo "Testing Data Science Pipelines Operator functionality"
verify_data_science_pipelines_operator_install
create_and_verify_data_science_pipelines_resources
create_pipeline
verify_pipeline_availabilty
create_run
verify_run_availabilty
check_run_status
delete_runs
delete_pipeline

os::test::junit::declare_suite_end