#!/usr/bin/env bats

load tests_helpers

COMPOSE_FILE=docker-compose-simple.yml
JENKINS_DOCKER_NETWORK_NAME=jenkins-envconsul-tests

function groovy_test(){
    run_groovy_script $COMPOSE_FILE groovy/envconsul/$1
}

@test ">>> setup envconsul tests env" {
    touch_config
    create_docker_network
    docker_compose_up docker-compose-consul.yml
    console_addr=$(docker-compose -f $TESTS_DIR/docker-compose-consul.yml port consul 8500)
    vault_addr=$(docker-compose -f $TESTS_DIR/docker-compose-consul.yml port vault 8200)
    health_check http://${console_addr}/v1/status/leader
    health_check http://${vault_addr}/v1/sys/health

    docker_compose_exec docker-compose-consul.yml consul consul kv put jenkins/git_password password
    docker_compose_exec docker-compose-consul.yml consul consul kv put jenkins/git_username username
    docker_compose_exec docker-compose-consul.yml vault vault write secret/jenkins top_secret=very_SECRET

    CONSUL_ADDR="consul:8500" \
    VAULT_TOKEN="vault-root-token" \
    VAULT_ADDR="http://vault:8200" \
    ENVCONSUL_CONSUL_PREFIX=jenkins \
    ENVCONSUL_VAULT_PREFIX="secret/jenkins" \
    ENVCONSUL_ADDITIONAL_ARGS="-vault-renew-token=false" \
    JENKINS_ENV_CONFIG_YML_URL=file://${TESTS_CONTAINER_CONF_DIR}/config.yml \
    docker_compose_up $COMPOSE_FILE
    jenkins_addr=$(docker-compose -f $TESTS_DIR/$COMPOSE_FILE port jenkins 8080)
    health_check http://${jenkins_addr}/login
}

@test "test values comming from consul" {
    config_from_fixture $TESTS_DIR/data/config-fixtures/creds-from-consul.yml
    sleep $SLEEP_TIME_BEFORE_CHECKS
    groovy_test AssertCredsFromConsul.groovy
}

@test "test values comming from vault" {
    config_from_fixture $TESTS_DIR/data/config-fixtures/creds-from-vault.yml
    sleep $SLEEP_TIME_BEFORE_CHECKS
    groovy_test AssertCredsFromVault.groovy
}

@test "<<< teardown envconsul tests env" {
    docker_compose_down docker-compose-consul.yml
    docker_compose_down $COMPOSE_FILE
    rm -rf $TESTS_HOST_CONF_DIR
    destroy_docker_network
}