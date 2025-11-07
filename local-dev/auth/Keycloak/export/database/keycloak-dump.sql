--
-- PostgreSQL database dump
--

-- Dumped from database version 17.5 (Debian 17.5-1.pgdg130+1)
-- Dumped by pg_dump version 17.5 (Debian 17.5-1.pgdg130+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: admin_event_entity; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.admin_event_entity (
    id character varying(36) NOT NULL,
    admin_event_time bigint,
    realm_id character varying(255),
    operation_type character varying(255),
    auth_realm_id character varying(255),
    auth_client_id character varying(255),
    auth_user_id character varying(255),
    ip_address character varying(255),
    resource_path character varying(2550),
    representation text,
    error character varying(255),
    resource_type character varying(64),
    details_json text
);


ALTER TABLE public.admin_event_entity OWNER TO postgres;

--
-- Name: associated_policy; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.associated_policy (
    policy_id character varying(36) NOT NULL,
    associated_policy_id character varying(36) NOT NULL
);


ALTER TABLE public.associated_policy OWNER TO postgres;

--
-- Name: authentication_execution; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.authentication_execution (
    id character varying(36) NOT NULL,
    alias character varying(255),
    authenticator character varying(36),
    realm_id character varying(36),
    flow_id character varying(36),
    requirement integer,
    priority integer,
    authenticator_flow boolean DEFAULT false NOT NULL,
    auth_flow_id character varying(36),
    auth_config character varying(36)
);


ALTER TABLE public.authentication_execution OWNER TO postgres;

--
-- Name: authentication_flow; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.authentication_flow (
    id character varying(36) NOT NULL,
    alias character varying(255),
    description character varying(255),
    realm_id character varying(36),
    provider_id character varying(36) DEFAULT 'basic-flow'::character varying NOT NULL,
    top_level boolean DEFAULT false NOT NULL,
    built_in boolean DEFAULT false NOT NULL
);


ALTER TABLE public.authentication_flow OWNER TO postgres;

--
-- Name: authenticator_config; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.authenticator_config (
    id character varying(36) NOT NULL,
    alias character varying(255),
    realm_id character varying(36)
);


ALTER TABLE public.authenticator_config OWNER TO postgres;

--
-- Name: authenticator_config_entry; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.authenticator_config_entry (
    authenticator_id character varying(36) NOT NULL,
    value text,
    name character varying(255) NOT NULL
);


ALTER TABLE public.authenticator_config_entry OWNER TO postgres;

--
-- Name: broker_link; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.broker_link (
    identity_provider character varying(255) NOT NULL,
    storage_provider_id character varying(255),
    realm_id character varying(36) NOT NULL,
    broker_user_id character varying(255),
    broker_username character varying(255),
    token text,
    user_id character varying(255) NOT NULL
);


ALTER TABLE public.broker_link OWNER TO postgres;

--
-- Name: client; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.client (
    id character varying(36) NOT NULL,
    enabled boolean DEFAULT false NOT NULL,
    full_scope_allowed boolean DEFAULT false NOT NULL,
    client_id character varying(255),
    not_before integer,
    public_client boolean DEFAULT false NOT NULL,
    secret character varying(255),
    base_url character varying(255),
    bearer_only boolean DEFAULT false NOT NULL,
    management_url character varying(255),
    surrogate_auth_required boolean DEFAULT false NOT NULL,
    realm_id character varying(36),
    protocol character varying(255),
    node_rereg_timeout integer DEFAULT 0,
    frontchannel_logout boolean DEFAULT false NOT NULL,
    consent_required boolean DEFAULT false NOT NULL,
    name character varying(255),
    service_accounts_enabled boolean DEFAULT false NOT NULL,
    client_authenticator_type character varying(255),
    root_url character varying(255),
    description character varying(255),
    registration_token character varying(255),
    standard_flow_enabled boolean DEFAULT true NOT NULL,
    implicit_flow_enabled boolean DEFAULT false NOT NULL,
    direct_access_grants_enabled boolean DEFAULT false NOT NULL,
    always_display_in_console boolean DEFAULT false NOT NULL
);


ALTER TABLE public.client OWNER TO postgres;

--
-- Name: client_attributes; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.client_attributes (
    client_id character varying(36) NOT NULL,
    name character varying(255) NOT NULL,
    value text
);


ALTER TABLE public.client_attributes OWNER TO postgres;

--
-- Name: client_auth_flow_bindings; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.client_auth_flow_bindings (
    client_id character varying(36) NOT NULL,
    flow_id character varying(36),
    binding_name character varying(255) NOT NULL
);


ALTER TABLE public.client_auth_flow_bindings OWNER TO postgres;

--
-- Name: client_initial_access; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.client_initial_access (
    id character varying(36) NOT NULL,
    realm_id character varying(36) NOT NULL,
    "timestamp" integer,
    expiration integer,
    count integer,
    remaining_count integer
);


ALTER TABLE public.client_initial_access OWNER TO postgres;

--
-- Name: client_node_registrations; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.client_node_registrations (
    client_id character varying(36) NOT NULL,
    value integer,
    name character varying(255) NOT NULL
);


ALTER TABLE public.client_node_registrations OWNER TO postgres;

--
-- Name: client_scope; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.client_scope (
    id character varying(36) NOT NULL,
    name character varying(255),
    realm_id character varying(36),
    description character varying(255),
    protocol character varying(255)
);


ALTER TABLE public.client_scope OWNER TO postgres;

--
-- Name: client_scope_attributes; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.client_scope_attributes (
    scope_id character varying(36) NOT NULL,
    value character varying(2048),
    name character varying(255) NOT NULL
);


ALTER TABLE public.client_scope_attributes OWNER TO postgres;

--
-- Name: client_scope_client; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.client_scope_client (
    client_id character varying(255) NOT NULL,
    scope_id character varying(255) NOT NULL,
    default_scope boolean DEFAULT false NOT NULL
);


ALTER TABLE public.client_scope_client OWNER TO postgres;

--
-- Name: client_scope_role_mapping; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.client_scope_role_mapping (
    scope_id character varying(36) NOT NULL,
    role_id character varying(36) NOT NULL
);


ALTER TABLE public.client_scope_role_mapping OWNER TO postgres;

--
-- Name: component; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.component (
    id character varying(36) NOT NULL,
    name character varying(255),
    parent_id character varying(36),
    provider_id character varying(36),
    provider_type character varying(255),
    realm_id character varying(36),
    sub_type character varying(255)
);


ALTER TABLE public.component OWNER TO postgres;

--
-- Name: component_config; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.component_config (
    id character varying(36) NOT NULL,
    component_id character varying(36) NOT NULL,
    name character varying(255) NOT NULL,
    value text
);


ALTER TABLE public.component_config OWNER TO postgres;

--
-- Name: composite_role; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.composite_role (
    composite character varying(36) NOT NULL,
    child_role character varying(36) NOT NULL
);


ALTER TABLE public.composite_role OWNER TO postgres;

--
-- Name: credential; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.credential (
    id character varying(36) NOT NULL,
    salt bytea,
    type character varying(255),
    user_id character varying(36),
    created_date bigint,
    user_label character varying(255),
    secret_data text,
    credential_data text,
    priority integer
);


ALTER TABLE public.credential OWNER TO postgres;

--
-- Name: databasechangelog; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.databasechangelog (
    id character varying(255) NOT NULL,
    author character varying(255) NOT NULL,
    filename character varying(255) NOT NULL,
    dateexecuted timestamp without time zone NOT NULL,
    orderexecuted integer NOT NULL,
    exectype character varying(10) NOT NULL,
    md5sum character varying(35),
    description character varying(255),
    comments character varying(255),
    tag character varying(255),
    liquibase character varying(20),
    contexts character varying(255),
    labels character varying(255),
    deployment_id character varying(10)
);


ALTER TABLE public.databasechangelog OWNER TO postgres;

--
-- Name: databasechangeloglock; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.databasechangeloglock (
    id integer NOT NULL,
    locked boolean NOT NULL,
    lockgranted timestamp without time zone,
    lockedby character varying(255)
);


ALTER TABLE public.databasechangeloglock OWNER TO postgres;

--
-- Name: default_client_scope; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.default_client_scope (
    realm_id character varying(36) NOT NULL,
    scope_id character varying(36) NOT NULL,
    default_scope boolean DEFAULT false NOT NULL
);


ALTER TABLE public.default_client_scope OWNER TO postgres;

--
-- Name: event_entity; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.event_entity (
    id character varying(36) NOT NULL,
    client_id character varying(255),
    details_json character varying(2550),
    error character varying(255),
    ip_address character varying(255),
    realm_id character varying(255),
    session_id character varying(255),
    event_time bigint,
    type character varying(255),
    user_id character varying(255),
    details_json_long_value text
);


ALTER TABLE public.event_entity OWNER TO postgres;

--
-- Name: fed_user_attribute; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fed_user_attribute (
    id character varying(36) NOT NULL,
    name character varying(255) NOT NULL,
    user_id character varying(255) NOT NULL,
    realm_id character varying(36) NOT NULL,
    storage_provider_id character varying(36),
    value character varying(2024),
    long_value_hash bytea,
    long_value_hash_lower_case bytea,
    long_value text
);


ALTER TABLE public.fed_user_attribute OWNER TO postgres;

--
-- Name: fed_user_consent; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fed_user_consent (
    id character varying(36) NOT NULL,
    client_id character varying(255),
    user_id character varying(255) NOT NULL,
    realm_id character varying(36) NOT NULL,
    storage_provider_id character varying(36),
    created_date bigint,
    last_updated_date bigint,
    client_storage_provider character varying(36),
    external_client_id character varying(255)
);


ALTER TABLE public.fed_user_consent OWNER TO postgres;

--
-- Name: fed_user_consent_cl_scope; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fed_user_consent_cl_scope (
    user_consent_id character varying(36) NOT NULL,
    scope_id character varying(36) NOT NULL
);


ALTER TABLE public.fed_user_consent_cl_scope OWNER TO postgres;

--
-- Name: fed_user_credential; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fed_user_credential (
    id character varying(36) NOT NULL,
    salt bytea,
    type character varying(255),
    created_date bigint,
    user_id character varying(255) NOT NULL,
    realm_id character varying(36) NOT NULL,
    storage_provider_id character varying(36),
    user_label character varying(255),
    secret_data text,
    credential_data text,
    priority integer
);


ALTER TABLE public.fed_user_credential OWNER TO postgres;

--
-- Name: fed_user_group_membership; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fed_user_group_membership (
    group_id character varying(36) NOT NULL,
    user_id character varying(255) NOT NULL,
    realm_id character varying(36) NOT NULL,
    storage_provider_id character varying(36)
);


ALTER TABLE public.fed_user_group_membership OWNER TO postgres;

--
-- Name: fed_user_required_action; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fed_user_required_action (
    required_action character varying(255) DEFAULT ' '::character varying NOT NULL,
    user_id character varying(255) NOT NULL,
    realm_id character varying(36) NOT NULL,
    storage_provider_id character varying(36)
);


ALTER TABLE public.fed_user_required_action OWNER TO postgres;

--
-- Name: fed_user_role_mapping; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fed_user_role_mapping (
    role_id character varying(36) NOT NULL,
    user_id character varying(255) NOT NULL,
    realm_id character varying(36) NOT NULL,
    storage_provider_id character varying(36)
);


ALTER TABLE public.fed_user_role_mapping OWNER TO postgres;

--
-- Name: federated_identity; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.federated_identity (
    identity_provider character varying(255) NOT NULL,
    realm_id character varying(36),
    federated_user_id character varying(255),
    federated_username character varying(255),
    token text,
    user_id character varying(36) NOT NULL
);


ALTER TABLE public.federated_identity OWNER TO postgres;

--
-- Name: federated_user; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.federated_user (
    id character varying(255) NOT NULL,
    storage_provider_id character varying(255),
    realm_id character varying(36) NOT NULL
);


ALTER TABLE public.federated_user OWNER TO postgres;

--
-- Name: group_attribute; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.group_attribute (
    id character varying(36) DEFAULT 'sybase-needs-something-here'::character varying NOT NULL,
    name character varying(255) NOT NULL,
    value character varying(255),
    group_id character varying(36) NOT NULL
);


ALTER TABLE public.group_attribute OWNER TO postgres;

--
-- Name: group_role_mapping; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.group_role_mapping (
    role_id character varying(36) NOT NULL,
    group_id character varying(36) NOT NULL
);


ALTER TABLE public.group_role_mapping OWNER TO postgres;

--
-- Name: identity_provider; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.identity_provider (
    internal_id character varying(36) NOT NULL,
    enabled boolean DEFAULT false NOT NULL,
    provider_alias character varying(255),
    provider_id character varying(255),
    store_token boolean DEFAULT false NOT NULL,
    authenticate_by_default boolean DEFAULT false NOT NULL,
    realm_id character varying(36),
    add_token_role boolean DEFAULT true NOT NULL,
    trust_email boolean DEFAULT false NOT NULL,
    first_broker_login_flow_id character varying(36),
    post_broker_login_flow_id character varying(36),
    provider_display_name character varying(255),
    link_only boolean DEFAULT false NOT NULL,
    organization_id character varying(255),
    hide_on_login boolean DEFAULT false
);


ALTER TABLE public.identity_provider OWNER TO postgres;

--
-- Name: identity_provider_config; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.identity_provider_config (
    identity_provider_id character varying(36) NOT NULL,
    value text,
    name character varying(255) NOT NULL
);


ALTER TABLE public.identity_provider_config OWNER TO postgres;

--
-- Name: identity_provider_mapper; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.identity_provider_mapper (
    id character varying(36) NOT NULL,
    name character varying(255) NOT NULL,
    idp_alias character varying(255) NOT NULL,
    idp_mapper_name character varying(255) NOT NULL,
    realm_id character varying(36) NOT NULL
);


ALTER TABLE public.identity_provider_mapper OWNER TO postgres;

--
-- Name: idp_mapper_config; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.idp_mapper_config (
    idp_mapper_id character varying(36) NOT NULL,
    value text,
    name character varying(255) NOT NULL
);


ALTER TABLE public.idp_mapper_config OWNER TO postgres;

--
-- Name: keycloak_group; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.keycloak_group (
    id character varying(36) NOT NULL,
    name character varying(255),
    parent_group character varying(36) NOT NULL,
    realm_id character varying(36),
    type integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.keycloak_group OWNER TO postgres;

--
-- Name: keycloak_role; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.keycloak_role (
    id character varying(36) NOT NULL,
    client_realm_constraint character varying(255),
    client_role boolean DEFAULT false NOT NULL,
    description character varying(255),
    name character varying(255),
    realm_id character varying(255),
    client character varying(36),
    realm character varying(36)
);


ALTER TABLE public.keycloak_role OWNER TO postgres;

--
-- Name: migration_model; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.migration_model (
    id character varying(36) NOT NULL,
    version character varying(36),
    update_time bigint DEFAULT 0 NOT NULL
);


ALTER TABLE public.migration_model OWNER TO postgres;

--
-- Name: offline_client_session; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.offline_client_session (
    user_session_id character varying(36) NOT NULL,
    client_id character varying(255) NOT NULL,
    offline_flag character varying(4) NOT NULL,
    "timestamp" integer,
    data text,
    client_storage_provider character varying(36) DEFAULT 'local'::character varying NOT NULL,
    external_client_id character varying(255) DEFAULT 'local'::character varying NOT NULL,
    version integer DEFAULT 0
);


ALTER TABLE public.offline_client_session OWNER TO postgres;

--
-- Name: offline_user_session; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.offline_user_session (
    user_session_id character varying(36) NOT NULL,
    user_id character varying(255) NOT NULL,
    realm_id character varying(36) NOT NULL,
    created_on integer NOT NULL,
    offline_flag character varying(4) NOT NULL,
    data text,
    last_session_refresh integer DEFAULT 0 NOT NULL,
    broker_session_id character varying(1024),
    version integer DEFAULT 0
);


ALTER TABLE public.offline_user_session OWNER TO postgres;

--
-- Name: org; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.org (
    id character varying(255) NOT NULL,
    enabled boolean NOT NULL,
    realm_id character varying(255) NOT NULL,
    group_id character varying(255) NOT NULL,
    name character varying(255) NOT NULL,
    description character varying(4000),
    alias character varying(255) NOT NULL,
    redirect_url character varying(2048)
);


ALTER TABLE public.org OWNER TO postgres;

--
-- Name: org_domain; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.org_domain (
    id character varying(36) NOT NULL,
    name character varying(255) NOT NULL,
    verified boolean NOT NULL,
    org_id character varying(255) NOT NULL
);


ALTER TABLE public.org_domain OWNER TO postgres;

--
-- Name: policy_config; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.policy_config (
    policy_id character varying(36) NOT NULL,
    name character varying(255) NOT NULL,
    value text
);


ALTER TABLE public.policy_config OWNER TO postgres;

--
-- Name: protocol_mapper; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.protocol_mapper (
    id character varying(36) NOT NULL,
    name character varying(255) NOT NULL,
    protocol character varying(255) NOT NULL,
    protocol_mapper_name character varying(255) NOT NULL,
    client_id character varying(36),
    client_scope_id character varying(36)
);


ALTER TABLE public.protocol_mapper OWNER TO postgres;

--
-- Name: protocol_mapper_config; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.protocol_mapper_config (
    protocol_mapper_id character varying(36) NOT NULL,
    value text,
    name character varying(255) NOT NULL
);


ALTER TABLE public.protocol_mapper_config OWNER TO postgres;

--
-- Name: realm; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.realm (
    id character varying(36) NOT NULL,
    access_code_lifespan integer,
    user_action_lifespan integer,
    access_token_lifespan integer,
    account_theme character varying(255),
    admin_theme character varying(255),
    email_theme character varying(255),
    enabled boolean DEFAULT false NOT NULL,
    events_enabled boolean DEFAULT false NOT NULL,
    events_expiration bigint,
    login_theme character varying(255),
    name character varying(255),
    not_before integer,
    password_policy character varying(2550),
    registration_allowed boolean DEFAULT false NOT NULL,
    remember_me boolean DEFAULT false NOT NULL,
    reset_password_allowed boolean DEFAULT false NOT NULL,
    social boolean DEFAULT false NOT NULL,
    ssl_required character varying(255),
    sso_idle_timeout integer,
    sso_max_lifespan integer,
    update_profile_on_soc_login boolean DEFAULT false NOT NULL,
    verify_email boolean DEFAULT false NOT NULL,
    master_admin_client character varying(36),
    login_lifespan integer,
    internationalization_enabled boolean DEFAULT false NOT NULL,
    default_locale character varying(255),
    reg_email_as_username boolean DEFAULT false NOT NULL,
    admin_events_enabled boolean DEFAULT false NOT NULL,
    admin_events_details_enabled boolean DEFAULT false NOT NULL,
    edit_username_allowed boolean DEFAULT false NOT NULL,
    otp_policy_counter integer DEFAULT 0,
    otp_policy_window integer DEFAULT 1,
    otp_policy_period integer DEFAULT 30,
    otp_policy_digits integer DEFAULT 6,
    otp_policy_alg character varying(36) DEFAULT 'HmacSHA1'::character varying,
    otp_policy_type character varying(36) DEFAULT 'totp'::character varying,
    browser_flow character varying(36),
    registration_flow character varying(36),
    direct_grant_flow character varying(36),
    reset_credentials_flow character varying(36),
    client_auth_flow character varying(36),
    offline_session_idle_timeout integer DEFAULT 0,
    revoke_refresh_token boolean DEFAULT false NOT NULL,
    access_token_life_implicit integer DEFAULT 0,
    login_with_email_allowed boolean DEFAULT true NOT NULL,
    duplicate_emails_allowed boolean DEFAULT false NOT NULL,
    docker_auth_flow character varying(36),
    refresh_token_max_reuse integer DEFAULT 0,
    allow_user_managed_access boolean DEFAULT false NOT NULL,
    sso_max_lifespan_remember_me integer DEFAULT 0 NOT NULL,
    sso_idle_timeout_remember_me integer DEFAULT 0 NOT NULL,
    default_role character varying(255)
);


ALTER TABLE public.realm OWNER TO postgres;

--
-- Name: realm_attribute; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.realm_attribute (
    name character varying(255) NOT NULL,
    realm_id character varying(36) NOT NULL,
    value text
);


ALTER TABLE public.realm_attribute OWNER TO postgres;

--
-- Name: realm_default_groups; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.realm_default_groups (
    realm_id character varying(36) NOT NULL,
    group_id character varying(36) NOT NULL
);


ALTER TABLE public.realm_default_groups OWNER TO postgres;

--
-- Name: realm_enabled_event_types; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.realm_enabled_event_types (
    realm_id character varying(36) NOT NULL,
    value character varying(255) NOT NULL
);


ALTER TABLE public.realm_enabled_event_types OWNER TO postgres;

--
-- Name: realm_events_listeners; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.realm_events_listeners (
    realm_id character varying(36) NOT NULL,
    value character varying(255) NOT NULL
);


ALTER TABLE public.realm_events_listeners OWNER TO postgres;

--
-- Name: realm_localizations; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.realm_localizations (
    realm_id character varying(255) NOT NULL,
    locale character varying(255) NOT NULL,
    texts text NOT NULL
);


ALTER TABLE public.realm_localizations OWNER TO postgres;

--
-- Name: realm_required_credential; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.realm_required_credential (
    type character varying(255) NOT NULL,
    form_label character varying(255),
    input boolean DEFAULT false NOT NULL,
    secret boolean DEFAULT false NOT NULL,
    realm_id character varying(36) NOT NULL
);


ALTER TABLE public.realm_required_credential OWNER TO postgres;

--
-- Name: realm_smtp_config; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.realm_smtp_config (
    realm_id character varying(36) NOT NULL,
    value character varying(255),
    name character varying(255) NOT NULL
);


ALTER TABLE public.realm_smtp_config OWNER TO postgres;

--
-- Name: realm_supported_locales; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.realm_supported_locales (
    realm_id character varying(36) NOT NULL,
    value character varying(255) NOT NULL
);


ALTER TABLE public.realm_supported_locales OWNER TO postgres;

--
-- Name: redirect_uris; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.redirect_uris (
    client_id character varying(36) NOT NULL,
    value character varying(255) NOT NULL
);


ALTER TABLE public.redirect_uris OWNER TO postgres;

--
-- Name: required_action_config; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.required_action_config (
    required_action_id character varying(36) NOT NULL,
    value text,
    name character varying(255) NOT NULL
);


ALTER TABLE public.required_action_config OWNER TO postgres;

--
-- Name: required_action_provider; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.required_action_provider (
    id character varying(36) NOT NULL,
    alias character varying(255),
    name character varying(255),
    realm_id character varying(36),
    enabled boolean DEFAULT false NOT NULL,
    default_action boolean DEFAULT false NOT NULL,
    provider_id character varying(255),
    priority integer
);


ALTER TABLE public.required_action_provider OWNER TO postgres;

--
-- Name: resource_attribute; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.resource_attribute (
    id character varying(36) DEFAULT 'sybase-needs-something-here'::character varying NOT NULL,
    name character varying(255) NOT NULL,
    value character varying(255),
    resource_id character varying(36) NOT NULL
);


ALTER TABLE public.resource_attribute OWNER TO postgres;

--
-- Name: resource_policy; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.resource_policy (
    resource_id character varying(36) NOT NULL,
    policy_id character varying(36) NOT NULL
);


ALTER TABLE public.resource_policy OWNER TO postgres;

--
-- Name: resource_scope; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.resource_scope (
    resource_id character varying(36) NOT NULL,
    scope_id character varying(36) NOT NULL
);


ALTER TABLE public.resource_scope OWNER TO postgres;

--
-- Name: resource_server; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.resource_server (
    id character varying(36) NOT NULL,
    allow_rs_remote_mgmt boolean DEFAULT false NOT NULL,
    policy_enforce_mode smallint NOT NULL,
    decision_strategy smallint DEFAULT 1 NOT NULL
);


ALTER TABLE public.resource_server OWNER TO postgres;

--
-- Name: resource_server_perm_ticket; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.resource_server_perm_ticket (
    id character varying(36) NOT NULL,
    owner character varying(255) NOT NULL,
    requester character varying(255) NOT NULL,
    created_timestamp bigint NOT NULL,
    granted_timestamp bigint,
    resource_id character varying(36) NOT NULL,
    scope_id character varying(36),
    resource_server_id character varying(36) NOT NULL,
    policy_id character varying(36)
);


ALTER TABLE public.resource_server_perm_ticket OWNER TO postgres;

--
-- Name: resource_server_policy; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.resource_server_policy (
    id character varying(36) NOT NULL,
    name character varying(255) NOT NULL,
    description character varying(255),
    type character varying(255) NOT NULL,
    decision_strategy smallint,
    logic smallint,
    resource_server_id character varying(36) NOT NULL,
    owner character varying(255)
);


ALTER TABLE public.resource_server_policy OWNER TO postgres;

--
-- Name: resource_server_resource; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.resource_server_resource (
    id character varying(36) NOT NULL,
    name character varying(255) NOT NULL,
    type character varying(255),
    icon_uri character varying(255),
    owner character varying(255) NOT NULL,
    resource_server_id character varying(36) NOT NULL,
    owner_managed_access boolean DEFAULT false NOT NULL,
    display_name character varying(255)
);


ALTER TABLE public.resource_server_resource OWNER TO postgres;

--
-- Name: resource_server_scope; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.resource_server_scope (
    id character varying(36) NOT NULL,
    name character varying(255) NOT NULL,
    icon_uri character varying(255),
    resource_server_id character varying(36) NOT NULL,
    display_name character varying(255)
);


ALTER TABLE public.resource_server_scope OWNER TO postgres;

--
-- Name: resource_uris; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.resource_uris (
    resource_id character varying(36) NOT NULL,
    value character varying(255) NOT NULL
);


ALTER TABLE public.resource_uris OWNER TO postgres;

--
-- Name: revoked_token; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.revoked_token (
    id character varying(255) NOT NULL,
    expire bigint NOT NULL
);


ALTER TABLE public.revoked_token OWNER TO postgres;

--
-- Name: role_attribute; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.role_attribute (
    id character varying(36) NOT NULL,
    role_id character varying(36) NOT NULL,
    name character varying(255) NOT NULL,
    value character varying(255)
);


ALTER TABLE public.role_attribute OWNER TO postgres;

--
-- Name: scope_mapping; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.scope_mapping (
    client_id character varying(36) NOT NULL,
    role_id character varying(36) NOT NULL
);


ALTER TABLE public.scope_mapping OWNER TO postgres;

--
-- Name: scope_policy; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.scope_policy (
    scope_id character varying(36) NOT NULL,
    policy_id character varying(36) NOT NULL
);


ALTER TABLE public.scope_policy OWNER TO postgres;

--
-- Name: user_attribute; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_attribute (
    name character varying(255) NOT NULL,
    value character varying(255),
    user_id character varying(36) NOT NULL,
    id character varying(36) DEFAULT 'sybase-needs-something-here'::character varying NOT NULL,
    long_value_hash bytea,
    long_value_hash_lower_case bytea,
    long_value text
);


ALTER TABLE public.user_attribute OWNER TO postgres;

--
-- Name: user_consent; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_consent (
    id character varying(36) NOT NULL,
    client_id character varying(255),
    user_id character varying(36) NOT NULL,
    created_date bigint,
    last_updated_date bigint,
    client_storage_provider character varying(36),
    external_client_id character varying(255)
);


ALTER TABLE public.user_consent OWNER TO postgres;

--
-- Name: user_consent_client_scope; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_consent_client_scope (
    user_consent_id character varying(36) NOT NULL,
    scope_id character varying(36) NOT NULL
);


ALTER TABLE public.user_consent_client_scope OWNER TO postgres;

--
-- Name: user_entity; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_entity (
    id character varying(36) NOT NULL,
    email character varying(255),
    email_constraint character varying(255),
    email_verified boolean DEFAULT false NOT NULL,
    enabled boolean DEFAULT false NOT NULL,
    federation_link character varying(255),
    first_name character varying(255),
    last_name character varying(255),
    realm_id character varying(255),
    username character varying(255),
    created_timestamp bigint,
    service_account_client_link character varying(255),
    not_before integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.user_entity OWNER TO postgres;

--
-- Name: user_federation_config; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_federation_config (
    user_federation_provider_id character varying(36) NOT NULL,
    value character varying(255),
    name character varying(255) NOT NULL
);


ALTER TABLE public.user_federation_config OWNER TO postgres;

--
-- Name: user_federation_mapper; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_federation_mapper (
    id character varying(36) NOT NULL,
    name character varying(255) NOT NULL,
    federation_provider_id character varying(36) NOT NULL,
    federation_mapper_type character varying(255) NOT NULL,
    realm_id character varying(36) NOT NULL
);


ALTER TABLE public.user_federation_mapper OWNER TO postgres;

--
-- Name: user_federation_mapper_config; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_federation_mapper_config (
    user_federation_mapper_id character varying(36) NOT NULL,
    value character varying(255),
    name character varying(255) NOT NULL
);


ALTER TABLE public.user_federation_mapper_config OWNER TO postgres;

--
-- Name: user_federation_provider; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_federation_provider (
    id character varying(36) NOT NULL,
    changed_sync_period integer,
    display_name character varying(255),
    full_sync_period integer,
    last_sync integer,
    priority integer,
    provider_name character varying(255),
    realm_id character varying(36)
);


ALTER TABLE public.user_federation_provider OWNER TO postgres;

--
-- Name: user_group_membership; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_group_membership (
    group_id character varying(36) NOT NULL,
    user_id character varying(36) NOT NULL,
    membership_type character varying(255) NOT NULL
);


ALTER TABLE public.user_group_membership OWNER TO postgres;

--
-- Name: user_required_action; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_required_action (
    user_id character varying(36) NOT NULL,
    required_action character varying(255) DEFAULT ' '::character varying NOT NULL
);


ALTER TABLE public.user_required_action OWNER TO postgres;

--
-- Name: user_role_mapping; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_role_mapping (
    role_id character varying(255) NOT NULL,
    user_id character varying(36) NOT NULL
);


ALTER TABLE public.user_role_mapping OWNER TO postgres;

--
-- Name: username_login_failure; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.username_login_failure (
    realm_id character varying(36) NOT NULL,
    username character varying(255) NOT NULL,
    failed_login_not_before integer,
    last_failure bigint,
    last_ip_failure character varying(255),
    num_failures integer
);


ALTER TABLE public.username_login_failure OWNER TO postgres;

--
-- Name: web_origins; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.web_origins (
    client_id character varying(36) NOT NULL,
    value character varying(255) NOT NULL
);


ALTER TABLE public.web_origins OWNER TO postgres;

--
-- Data for Name: admin_event_entity; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.admin_event_entity (id, admin_event_time, realm_id, operation_type, auth_realm_id, auth_client_id, auth_user_id, ip_address, resource_path, representation, error, resource_type, details_json) FROM stdin;
\.


--
-- Data for Name: associated_policy; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.associated_policy (policy_id, associated_policy_id) FROM stdin;
2c907709-c0fa-48bf-bf7a-3e0900464a00	2954b2a2-7a31-4064-918e-6cb0d75cf43a
f2a0b9fb-9f81-408d-9d85-5179936edbb4	385360f0-fe21-476f-aa17-6364f7ee537e
\.


--
-- Data for Name: authentication_execution; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.authentication_execution (id, alias, authenticator, realm_id, flow_id, requirement, priority, authenticator_flow, auth_flow_id, auth_config) FROM stdin;
b7845cca-4fbb-4e4a-8396-7c63cb0aeb21	\N	auth-cookie	5be18a3e-7181-4862-867b-45aff91b9b87	5f8cbd27-a53c-4a85-bf5a-732d316a490a	2	10	f	\N	\N
32a56d22-8952-497c-b611-3db6c8f22cc4	\N	auth-spnego	5be18a3e-7181-4862-867b-45aff91b9b87	5f8cbd27-a53c-4a85-bf5a-732d316a490a	3	20	f	\N	\N
6c37a867-4286-41c7-8020-36042e721a9d	\N	identity-provider-redirector	5be18a3e-7181-4862-867b-45aff91b9b87	5f8cbd27-a53c-4a85-bf5a-732d316a490a	2	25	f	\N	\N
5404c169-0c95-4ba7-bd7e-0bd5d853ce8c	\N	\N	5be18a3e-7181-4862-867b-45aff91b9b87	5f8cbd27-a53c-4a85-bf5a-732d316a490a	2	30	t	6e15b791-9b56-4cb6-aeed-a5fcd857f0bd	\N
b97aaa37-a74c-4b5d-bd85-c23a439e382c	\N	auth-username-password-form	5be18a3e-7181-4862-867b-45aff91b9b87	6e15b791-9b56-4cb6-aeed-a5fcd857f0bd	0	10	f	\N	\N
48e0226d-a2a8-4543-9d4a-2e94b241be42	\N	\N	5be18a3e-7181-4862-867b-45aff91b9b87	6e15b791-9b56-4cb6-aeed-a5fcd857f0bd	1	20	t	a609969a-0331-40b7-9c71-9bcd828afec5	\N
93f8d34d-85ea-4c61-b9f7-8d3bb71e4fc8	\N	conditional-user-configured	5be18a3e-7181-4862-867b-45aff91b9b87	a609969a-0331-40b7-9c71-9bcd828afec5	0	10	f	\N	\N
eca0f2e5-1a1d-4539-a8b0-abff96a7b4c0	\N	auth-otp-form	5be18a3e-7181-4862-867b-45aff91b9b87	a609969a-0331-40b7-9c71-9bcd828afec5	0	20	f	\N	\N
8144e794-f696-4ee3-ad56-11ea179813a2	\N	direct-grant-validate-username	5be18a3e-7181-4862-867b-45aff91b9b87	984c5708-0406-4d68-80dc-6e8ecf273d35	0	10	f	\N	\N
1b5e1098-9055-4068-b453-6f97e8259cea	\N	direct-grant-validate-password	5be18a3e-7181-4862-867b-45aff91b9b87	984c5708-0406-4d68-80dc-6e8ecf273d35	0	20	f	\N	\N
334ea4df-0497-4280-bcbb-a496e9aab9df	\N	\N	5be18a3e-7181-4862-867b-45aff91b9b87	984c5708-0406-4d68-80dc-6e8ecf273d35	1	30	t	602661cf-b80f-4d1b-80dc-7b7a9cddc7d6	\N
056b5bea-5ac8-4a8b-877d-84bb13c00528	\N	conditional-user-configured	5be18a3e-7181-4862-867b-45aff91b9b87	602661cf-b80f-4d1b-80dc-7b7a9cddc7d6	0	10	f	\N	\N
4863a7d5-ebdc-4900-a6dc-d65be4eb8909	\N	direct-grant-validate-otp	5be18a3e-7181-4862-867b-45aff91b9b87	602661cf-b80f-4d1b-80dc-7b7a9cddc7d6	0	20	f	\N	\N
baca15da-a7b5-4962-b40e-c4bc717dafad	\N	registration-page-form	5be18a3e-7181-4862-867b-45aff91b9b87	1471d3f0-431f-4182-a32e-a9d1086fe058	0	10	t	04ca5622-e58c-4ed3-8155-8c22634f575c	\N
f5de57d4-a040-415f-ade0-d3ee8021691d	\N	registration-user-creation	5be18a3e-7181-4862-867b-45aff91b9b87	04ca5622-e58c-4ed3-8155-8c22634f575c	0	20	f	\N	\N
8984edaa-b4bc-4359-a836-4aeaf37cd1b2	\N	registration-password-action	5be18a3e-7181-4862-867b-45aff91b9b87	04ca5622-e58c-4ed3-8155-8c22634f575c	0	50	f	\N	\N
3f333f47-8dbe-43f6-b706-bb561a017076	\N	registration-recaptcha-action	5be18a3e-7181-4862-867b-45aff91b9b87	04ca5622-e58c-4ed3-8155-8c22634f575c	3	60	f	\N	\N
4bfddd2c-605e-48a8-a114-f44f32683b39	\N	registration-terms-and-conditions	5be18a3e-7181-4862-867b-45aff91b9b87	04ca5622-e58c-4ed3-8155-8c22634f575c	3	70	f	\N	\N
8a236a95-a59b-41a3-beba-4e35f3ea0da1	\N	reset-credentials-choose-user	5be18a3e-7181-4862-867b-45aff91b9b87	4136924b-30e5-4f37-85bb-2784db2be1c2	0	10	f	\N	\N
533dfde0-0147-4716-a2fc-3cc0e5e6ec3d	\N	reset-credential-email	5be18a3e-7181-4862-867b-45aff91b9b87	4136924b-30e5-4f37-85bb-2784db2be1c2	0	20	f	\N	\N
496205b3-c457-45ad-a511-0ca21adf6049	\N	reset-password	5be18a3e-7181-4862-867b-45aff91b9b87	4136924b-30e5-4f37-85bb-2784db2be1c2	0	30	f	\N	\N
9d9837e5-78bf-4865-b0d6-431dd1a2d75c	\N	\N	5be18a3e-7181-4862-867b-45aff91b9b87	4136924b-30e5-4f37-85bb-2784db2be1c2	1	40	t	1c88deb9-ff64-431f-93ad-d472ca405c81	\N
62d4a2e2-9753-48c3-bd63-df08e8b16c39	\N	conditional-user-configured	5be18a3e-7181-4862-867b-45aff91b9b87	1c88deb9-ff64-431f-93ad-d472ca405c81	0	10	f	\N	\N
823442bb-46c8-4317-b017-ee6e3507bd42	\N	reset-otp	5be18a3e-7181-4862-867b-45aff91b9b87	1c88deb9-ff64-431f-93ad-d472ca405c81	0	20	f	\N	\N
9dcc0528-83c4-4283-925a-771758d80331	\N	client-secret	5be18a3e-7181-4862-867b-45aff91b9b87	4890f38e-a236-4160-9e34-0dded0a9f766	2	10	f	\N	\N
36e4ea98-032a-46c2-b955-c794906bfcf0	\N	client-jwt	5be18a3e-7181-4862-867b-45aff91b9b87	4890f38e-a236-4160-9e34-0dded0a9f766	2	20	f	\N	\N
084524b0-b027-44a3-b037-fc35031f0092	\N	client-secret-jwt	5be18a3e-7181-4862-867b-45aff91b9b87	4890f38e-a236-4160-9e34-0dded0a9f766	2	30	f	\N	\N
8d3bd157-aa1d-4ad6-b777-d881de403f31	\N	client-x509	5be18a3e-7181-4862-867b-45aff91b9b87	4890f38e-a236-4160-9e34-0dded0a9f766	2	40	f	\N	\N
b52043c7-05ba-4881-85bd-4e5d3b7a1e73	\N	idp-review-profile	5be18a3e-7181-4862-867b-45aff91b9b87	3a315df6-567c-4d74-9e76-04a42cb85cdf	0	10	f	\N	af98a68b-5df1-4215-a7ff-1ca9c8673df8
ead2445a-abd5-4c3d-abca-95ec9f6db770	\N	\N	5be18a3e-7181-4862-867b-45aff91b9b87	3a315df6-567c-4d74-9e76-04a42cb85cdf	0	20	t	c97b2994-7fcf-4ec4-bcaa-8496567253e2	\N
e0a2abc5-d7f7-4f6e-bb1c-6a709933d9f3	\N	idp-create-user-if-unique	5be18a3e-7181-4862-867b-45aff91b9b87	c97b2994-7fcf-4ec4-bcaa-8496567253e2	2	10	f	\N	2e70c740-3a12-46a1-8b5a-88e04b80c6ba
81f4d05d-b190-46c7-bb45-0cf22215180a	\N	\N	5be18a3e-7181-4862-867b-45aff91b9b87	c97b2994-7fcf-4ec4-bcaa-8496567253e2	2	20	t	a59f3267-5975-4cb0-8590-47aaa86fce63	\N
93142dcb-d578-479b-83cd-ff33dbc4cfed	\N	idp-confirm-link	5be18a3e-7181-4862-867b-45aff91b9b87	a59f3267-5975-4cb0-8590-47aaa86fce63	0	10	f	\N	\N
d39a9f14-162a-45dd-999c-5b5017bc0f1f	\N	\N	5be18a3e-7181-4862-867b-45aff91b9b87	a59f3267-5975-4cb0-8590-47aaa86fce63	0	20	t	af4d27ad-503c-4b2f-bd3f-eaac736eaa88	\N
1be1660f-268b-4a47-83cc-e6e7ecc3350a	\N	idp-email-verification	5be18a3e-7181-4862-867b-45aff91b9b87	af4d27ad-503c-4b2f-bd3f-eaac736eaa88	2	10	f	\N	\N
a695c19d-54d8-4640-9b3f-9cc7c99821da	\N	\N	5be18a3e-7181-4862-867b-45aff91b9b87	af4d27ad-503c-4b2f-bd3f-eaac736eaa88	2	20	t	3587fd28-427e-4f5a-96cb-caafae613e3e	\N
2f1b7156-aee5-4d1e-8ad5-3dda25dc7323	\N	idp-username-password-form	5be18a3e-7181-4862-867b-45aff91b9b87	3587fd28-427e-4f5a-96cb-caafae613e3e	0	10	f	\N	\N
a1e99791-394a-4438-a061-c9515c4250d3	\N	\N	5be18a3e-7181-4862-867b-45aff91b9b87	3587fd28-427e-4f5a-96cb-caafae613e3e	1	20	t	b13caa4e-cc37-43c7-8e20-3e7076af7337	\N
f9e1f86c-0212-4118-822d-6a35d43f6192	\N	conditional-user-configured	5be18a3e-7181-4862-867b-45aff91b9b87	b13caa4e-cc37-43c7-8e20-3e7076af7337	0	10	f	\N	\N
12584446-3d79-487b-97f1-5cce432cb6ef	\N	auth-otp-form	5be18a3e-7181-4862-867b-45aff91b9b87	b13caa4e-cc37-43c7-8e20-3e7076af7337	0	20	f	\N	\N
ca6e9bd8-072e-450e-820c-14b2875f47e8	\N	http-basic-authenticator	5be18a3e-7181-4862-867b-45aff91b9b87	1fcf18f4-e6f4-4a85-b196-e28d382bf19e	0	10	f	\N	\N
33d34bb4-8495-4eff-a014-4a134b8ce3f9	\N	docker-http-basic-authenticator	5be18a3e-7181-4862-867b-45aff91b9b87	cc75ac9c-238d-48a0-9231-fdbd47609884	0	10	f	\N	\N
a55d55ff-de84-43eb-aad0-20e0f0ac19be	\N	auth-cookie	21dfe33f-5923-4bfd-bc04-cf200e747656	18f8930d-937f-4cfe-9759-456f27b2fbcd	2	10	f	\N	\N
09eed959-1005-4d35-ba78-9cdb1bcde26d	\N	auth-spnego	21dfe33f-5923-4bfd-bc04-cf200e747656	18f8930d-937f-4cfe-9759-456f27b2fbcd	3	20	f	\N	\N
10341fe1-2ad5-47c0-bbc4-eb319c2c5df1	\N	identity-provider-redirector	21dfe33f-5923-4bfd-bc04-cf200e747656	18f8930d-937f-4cfe-9759-456f27b2fbcd	2	25	f	\N	\N
ee22fd7d-732a-4dd9-9701-c700b6dba778	\N	\N	21dfe33f-5923-4bfd-bc04-cf200e747656	18f8930d-937f-4cfe-9759-456f27b2fbcd	2	30	t	8438c92c-7ad0-462c-be3a-32b95b28ca73	\N
f3d6f551-e7ea-4f7e-924f-da55c56e1d9a	\N	auth-username-password-form	21dfe33f-5923-4bfd-bc04-cf200e747656	8438c92c-7ad0-462c-be3a-32b95b28ca73	0	10	f	\N	\N
ade06a5a-a78f-46d1-9ad8-167e3b3431c2	\N	\N	21dfe33f-5923-4bfd-bc04-cf200e747656	8438c92c-7ad0-462c-be3a-32b95b28ca73	1	20	t	37ac9628-ed8c-4a17-ac58-05a4c0bacd80	\N
2188a2f9-d463-4d6d-a4d3-6c3bda6128d1	\N	conditional-user-configured	21dfe33f-5923-4bfd-bc04-cf200e747656	37ac9628-ed8c-4a17-ac58-05a4c0bacd80	0	10	f	\N	\N
951a12ed-a0a3-4af7-a215-a3e969597b69	\N	auth-otp-form	21dfe33f-5923-4bfd-bc04-cf200e747656	37ac9628-ed8c-4a17-ac58-05a4c0bacd80	0	20	f	\N	\N
e2d20500-a075-46e1-ab7d-1b6a9544f74f	\N	\N	21dfe33f-5923-4bfd-bc04-cf200e747656	18f8930d-937f-4cfe-9759-456f27b2fbcd	2	26	t	fef52f82-2978-4bae-bf5e-a5500aab24c1	\N
d8f3d1c5-9292-466e-81fc-885e3aa73031	\N	\N	21dfe33f-5923-4bfd-bc04-cf200e747656	fef52f82-2978-4bae-bf5e-a5500aab24c1	1	10	t	23b8a3ad-26e1-4b1d-8310-6f547b80051f	\N
f4ce4e5b-7e6f-49d3-9ea1-118632f83082	\N	conditional-user-configured	21dfe33f-5923-4bfd-bc04-cf200e747656	23b8a3ad-26e1-4b1d-8310-6f547b80051f	0	10	f	\N	\N
22f4a12f-ec42-4501-97bf-bba63c904d8a	\N	organization	21dfe33f-5923-4bfd-bc04-cf200e747656	23b8a3ad-26e1-4b1d-8310-6f547b80051f	2	20	f	\N	\N
89ca3635-a445-496d-b709-929e95c93511	\N	direct-grant-validate-username	21dfe33f-5923-4bfd-bc04-cf200e747656	901b8bca-2737-4d93-97af-1c0705c1f696	0	10	f	\N	\N
9153b489-9b6d-468b-b25f-44e14090d8dd	\N	direct-grant-validate-password	21dfe33f-5923-4bfd-bc04-cf200e747656	901b8bca-2737-4d93-97af-1c0705c1f696	0	20	f	\N	\N
6960fc9d-404b-4c71-9fc8-e57a16dca66b	\N	\N	21dfe33f-5923-4bfd-bc04-cf200e747656	901b8bca-2737-4d93-97af-1c0705c1f696	1	30	t	23985526-2a23-4762-b801-30fd3847fd56	\N
50a9dec2-dd31-4717-a9c4-a3bbf109974b	\N	conditional-user-configured	21dfe33f-5923-4bfd-bc04-cf200e747656	23985526-2a23-4762-b801-30fd3847fd56	0	10	f	\N	\N
6a0856c8-dcce-4d92-b6bb-11e760fc6ef9	\N	direct-grant-validate-otp	21dfe33f-5923-4bfd-bc04-cf200e747656	23985526-2a23-4762-b801-30fd3847fd56	0	20	f	\N	\N
0e390b83-7de7-45e9-907a-5748d6be0eba	\N	registration-page-form	21dfe33f-5923-4bfd-bc04-cf200e747656	1b430291-7568-4736-9f5d-41397ae77c84	0	10	t	4e4d74a7-0075-4894-a1d0-f63ccbeefe8b	\N
bba2785b-d0ab-4af9-a79a-3007972115e5	\N	registration-user-creation	21dfe33f-5923-4bfd-bc04-cf200e747656	4e4d74a7-0075-4894-a1d0-f63ccbeefe8b	0	20	f	\N	\N
51e1fb00-65d0-487f-ab93-09a28ae75ee6	\N	registration-password-action	21dfe33f-5923-4bfd-bc04-cf200e747656	4e4d74a7-0075-4894-a1d0-f63ccbeefe8b	0	50	f	\N	\N
910841f3-c621-4a84-a848-443aa3654dc0	\N	registration-recaptcha-action	21dfe33f-5923-4bfd-bc04-cf200e747656	4e4d74a7-0075-4894-a1d0-f63ccbeefe8b	3	60	f	\N	\N
f2bd13ce-6910-4cef-981f-34e7f61cf4f4	\N	registration-terms-and-conditions	21dfe33f-5923-4bfd-bc04-cf200e747656	4e4d74a7-0075-4894-a1d0-f63ccbeefe8b	3	70	f	\N	\N
871176dc-f2e6-4f42-ae8e-05c78ccfcc13	\N	reset-credentials-choose-user	21dfe33f-5923-4bfd-bc04-cf200e747656	c03b6bd8-c892-4f47-98c7-884c4aa231f8	0	10	f	\N	\N
84af284c-0508-457f-9579-0d2470a22531	\N	reset-credential-email	21dfe33f-5923-4bfd-bc04-cf200e747656	c03b6bd8-c892-4f47-98c7-884c4aa231f8	0	20	f	\N	\N
3fcb8e65-61f5-4fae-bdd7-80878b159920	\N	reset-password	21dfe33f-5923-4bfd-bc04-cf200e747656	c03b6bd8-c892-4f47-98c7-884c4aa231f8	0	30	f	\N	\N
547303ac-79bf-4a6d-8635-99d1d22d1d1a	\N	\N	21dfe33f-5923-4bfd-bc04-cf200e747656	c03b6bd8-c892-4f47-98c7-884c4aa231f8	1	40	t	2320f5aa-0cb5-49cb-a9e1-c56fc1d7d9e0	\N
e049ba59-47f3-4f9d-a577-b262c11e199a	\N	conditional-user-configured	21dfe33f-5923-4bfd-bc04-cf200e747656	2320f5aa-0cb5-49cb-a9e1-c56fc1d7d9e0	0	10	f	\N	\N
6f1fdc55-3dd1-4578-a0f0-6ed522aaa192	\N	reset-otp	21dfe33f-5923-4bfd-bc04-cf200e747656	2320f5aa-0cb5-49cb-a9e1-c56fc1d7d9e0	0	20	f	\N	\N
953f5b65-f8b6-47e9-824d-073ca6979358	\N	client-secret	21dfe33f-5923-4bfd-bc04-cf200e747656	c4586673-35ac-4310-91ce-8d82acabd5b2	2	10	f	\N	\N
ff14a5da-60c5-469a-9a24-b103bd758966	\N	client-jwt	21dfe33f-5923-4bfd-bc04-cf200e747656	c4586673-35ac-4310-91ce-8d82acabd5b2	2	20	f	\N	\N
8fce81d2-a3d2-4b8e-9e02-125792cd9335	\N	client-secret-jwt	21dfe33f-5923-4bfd-bc04-cf200e747656	c4586673-35ac-4310-91ce-8d82acabd5b2	2	30	f	\N	\N
9304c88a-b155-469b-8eb8-6ef7141cbe99	\N	client-x509	21dfe33f-5923-4bfd-bc04-cf200e747656	c4586673-35ac-4310-91ce-8d82acabd5b2	2	40	f	\N	\N
5f831155-9400-4787-9875-d0b8bfb83963	\N	idp-review-profile	21dfe33f-5923-4bfd-bc04-cf200e747656	e649748d-6a9d-403a-87c2-8f0c05d06519	0	10	f	\N	5d79c34d-7837-411d-b64c-89d5cfd58098
fbd04e34-e03c-4354-beee-44f62448e8c1	\N	\N	21dfe33f-5923-4bfd-bc04-cf200e747656	e649748d-6a9d-403a-87c2-8f0c05d06519	0	20	t	b583b84e-5152-48f6-bfc3-566ae3a8fcc8	\N
6dbd2f98-5253-4bdb-9829-d963b4ee765a	\N	idp-create-user-if-unique	21dfe33f-5923-4bfd-bc04-cf200e747656	b583b84e-5152-48f6-bfc3-566ae3a8fcc8	2	10	f	\N	037e8455-f731-4e71-9340-bcdbacb4053a
45a63b6c-bcc8-4e22-a9f3-155d0ed282e7	\N	\N	21dfe33f-5923-4bfd-bc04-cf200e747656	b583b84e-5152-48f6-bfc3-566ae3a8fcc8	2	20	t	2f967780-8d62-416c-b2c4-4072d44dc08e	\N
10ac340b-78c7-421d-8da1-29818b11ef76	\N	idp-confirm-link	21dfe33f-5923-4bfd-bc04-cf200e747656	2f967780-8d62-416c-b2c4-4072d44dc08e	0	10	f	\N	\N
1bf916a5-4079-4ab7-a6e0-c76cf8465dd0	\N	\N	21dfe33f-5923-4bfd-bc04-cf200e747656	2f967780-8d62-416c-b2c4-4072d44dc08e	0	20	t	52056be6-e28c-4361-9389-58937e3aef97	\N
5c186d9f-f771-44dd-be4e-ac160e201a1a	\N	idp-email-verification	21dfe33f-5923-4bfd-bc04-cf200e747656	52056be6-e28c-4361-9389-58937e3aef97	2	10	f	\N	\N
e2eb307a-a0ae-4ae8-a2ac-fcc61deffca2	\N	\N	21dfe33f-5923-4bfd-bc04-cf200e747656	52056be6-e28c-4361-9389-58937e3aef97	2	20	t	e4e3f108-5c38-45f9-92ad-79af7dcd778e	\N
4e1c8aba-244d-4396-b50a-6790adb9679c	\N	idp-username-password-form	21dfe33f-5923-4bfd-bc04-cf200e747656	e4e3f108-5c38-45f9-92ad-79af7dcd778e	0	10	f	\N	\N
a068b1a5-b0af-40c2-a35c-5c113e8e61c6	\N	\N	21dfe33f-5923-4bfd-bc04-cf200e747656	e4e3f108-5c38-45f9-92ad-79af7dcd778e	1	20	t	f73cfdc9-6f33-4bdb-a6d4-dc428757289a	\N
d688b70d-a0f0-49cf-9938-d2c9e5962eb3	\N	conditional-user-configured	21dfe33f-5923-4bfd-bc04-cf200e747656	f73cfdc9-6f33-4bdb-a6d4-dc428757289a	0	10	f	\N	\N
998f876c-6ae3-44fb-9ff6-8409e553fa1d	\N	auth-otp-form	21dfe33f-5923-4bfd-bc04-cf200e747656	f73cfdc9-6f33-4bdb-a6d4-dc428757289a	0	20	f	\N	\N
0fce5fcf-9ab2-44d9-8f9c-d8a4182dbdac	\N	\N	21dfe33f-5923-4bfd-bc04-cf200e747656	e649748d-6a9d-403a-87c2-8f0c05d06519	1	50	t	3fd1dcad-8892-49dd-9cfc-fa8a0cc40356	\N
767166bb-81bd-49c2-899d-a08b19baf3cf	\N	conditional-user-configured	21dfe33f-5923-4bfd-bc04-cf200e747656	3fd1dcad-8892-49dd-9cfc-fa8a0cc40356	0	10	f	\N	\N
811a1b03-3672-444a-a942-e4b51b3f3a4f	\N	idp-add-organization-member	21dfe33f-5923-4bfd-bc04-cf200e747656	3fd1dcad-8892-49dd-9cfc-fa8a0cc40356	0	20	f	\N	\N
71989709-7afb-47af-8b9a-9e5698dfd342	\N	http-basic-authenticator	21dfe33f-5923-4bfd-bc04-cf200e747656	4c6d14b5-f912-473b-9037-bd4de57ac95f	0	10	f	\N	\N
3870f750-b527-44e3-bf3e-83f195713905	\N	docker-http-basic-authenticator	21dfe33f-5923-4bfd-bc04-cf200e747656	03c9b0c7-1b02-4b5b-93ca-d94f5fff38c6	0	10	f	\N	\N
\.


--
-- Data for Name: authentication_flow; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.authentication_flow (id, alias, description, realm_id, provider_id, top_level, built_in) FROM stdin;
5f8cbd27-a53c-4a85-bf5a-732d316a490a	browser	Browser based authentication	5be18a3e-7181-4862-867b-45aff91b9b87	basic-flow	t	t
6e15b791-9b56-4cb6-aeed-a5fcd857f0bd	forms	Username, password, otp and other auth forms.	5be18a3e-7181-4862-867b-45aff91b9b87	basic-flow	f	t
a609969a-0331-40b7-9c71-9bcd828afec5	Browser - Conditional OTP	Flow to determine if the OTP is required for the authentication	5be18a3e-7181-4862-867b-45aff91b9b87	basic-flow	f	t
984c5708-0406-4d68-80dc-6e8ecf273d35	direct grant	OpenID Connect Resource Owner Grant	5be18a3e-7181-4862-867b-45aff91b9b87	basic-flow	t	t
602661cf-b80f-4d1b-80dc-7b7a9cddc7d6	Direct Grant - Conditional OTP	Flow to determine if the OTP is required for the authentication	5be18a3e-7181-4862-867b-45aff91b9b87	basic-flow	f	t
1471d3f0-431f-4182-a32e-a9d1086fe058	registration	Registration flow	5be18a3e-7181-4862-867b-45aff91b9b87	basic-flow	t	t
04ca5622-e58c-4ed3-8155-8c22634f575c	registration form	Registration form	5be18a3e-7181-4862-867b-45aff91b9b87	form-flow	f	t
4136924b-30e5-4f37-85bb-2784db2be1c2	reset credentials	Reset credentials for a user if they forgot their password or something	5be18a3e-7181-4862-867b-45aff91b9b87	basic-flow	t	t
1c88deb9-ff64-431f-93ad-d472ca405c81	Reset - Conditional OTP	Flow to determine if the OTP should be reset or not. Set to REQUIRED to force.	5be18a3e-7181-4862-867b-45aff91b9b87	basic-flow	f	t
4890f38e-a236-4160-9e34-0dded0a9f766	clients	Base authentication for clients	5be18a3e-7181-4862-867b-45aff91b9b87	client-flow	t	t
3a315df6-567c-4d74-9e76-04a42cb85cdf	first broker login	Actions taken after first broker login with identity provider account, which is not yet linked to any Keycloak account	5be18a3e-7181-4862-867b-45aff91b9b87	basic-flow	t	t
c97b2994-7fcf-4ec4-bcaa-8496567253e2	User creation or linking	Flow for the existing/non-existing user alternatives	5be18a3e-7181-4862-867b-45aff91b9b87	basic-flow	f	t
a59f3267-5975-4cb0-8590-47aaa86fce63	Handle Existing Account	Handle what to do if there is existing account with same email/username like authenticated identity provider	5be18a3e-7181-4862-867b-45aff91b9b87	basic-flow	f	t
af4d27ad-503c-4b2f-bd3f-eaac736eaa88	Account verification options	Method with which to verity the existing account	5be18a3e-7181-4862-867b-45aff91b9b87	basic-flow	f	t
3587fd28-427e-4f5a-96cb-caafae613e3e	Verify Existing Account by Re-authentication	Reauthentication of existing account	5be18a3e-7181-4862-867b-45aff91b9b87	basic-flow	f	t
b13caa4e-cc37-43c7-8e20-3e7076af7337	First broker login - Conditional OTP	Flow to determine if the OTP is required for the authentication	5be18a3e-7181-4862-867b-45aff91b9b87	basic-flow	f	t
1fcf18f4-e6f4-4a85-b196-e28d382bf19e	saml ecp	SAML ECP Profile Authentication Flow	5be18a3e-7181-4862-867b-45aff91b9b87	basic-flow	t	t
cc75ac9c-238d-48a0-9231-fdbd47609884	docker auth	Used by Docker clients to authenticate against the IDP	5be18a3e-7181-4862-867b-45aff91b9b87	basic-flow	t	t
18f8930d-937f-4cfe-9759-456f27b2fbcd	browser	Browser based authentication	21dfe33f-5923-4bfd-bc04-cf200e747656	basic-flow	t	t
8438c92c-7ad0-462c-be3a-32b95b28ca73	forms	Username, password, otp and other auth forms.	21dfe33f-5923-4bfd-bc04-cf200e747656	basic-flow	f	t
37ac9628-ed8c-4a17-ac58-05a4c0bacd80	Browser - Conditional OTP	Flow to determine if the OTP is required for the authentication	21dfe33f-5923-4bfd-bc04-cf200e747656	basic-flow	f	t
fef52f82-2978-4bae-bf5e-a5500aab24c1	Organization	\N	21dfe33f-5923-4bfd-bc04-cf200e747656	basic-flow	f	t
23b8a3ad-26e1-4b1d-8310-6f547b80051f	Browser - Conditional Organization	Flow to determine if the organization identity-first login is to be used	21dfe33f-5923-4bfd-bc04-cf200e747656	basic-flow	f	t
901b8bca-2737-4d93-97af-1c0705c1f696	direct grant	OpenID Connect Resource Owner Grant	21dfe33f-5923-4bfd-bc04-cf200e747656	basic-flow	t	t
23985526-2a23-4762-b801-30fd3847fd56	Direct Grant - Conditional OTP	Flow to determine if the OTP is required for the authentication	21dfe33f-5923-4bfd-bc04-cf200e747656	basic-flow	f	t
1b430291-7568-4736-9f5d-41397ae77c84	registration	Registration flow	21dfe33f-5923-4bfd-bc04-cf200e747656	basic-flow	t	t
4e4d74a7-0075-4894-a1d0-f63ccbeefe8b	registration form	Registration form	21dfe33f-5923-4bfd-bc04-cf200e747656	form-flow	f	t
c03b6bd8-c892-4f47-98c7-884c4aa231f8	reset credentials	Reset credentials for a user if they forgot their password or something	21dfe33f-5923-4bfd-bc04-cf200e747656	basic-flow	t	t
2320f5aa-0cb5-49cb-a9e1-c56fc1d7d9e0	Reset - Conditional OTP	Flow to determine if the OTP should be reset or not. Set to REQUIRED to force.	21dfe33f-5923-4bfd-bc04-cf200e747656	basic-flow	f	t
c4586673-35ac-4310-91ce-8d82acabd5b2	clients	Base authentication for clients	21dfe33f-5923-4bfd-bc04-cf200e747656	client-flow	t	t
e649748d-6a9d-403a-87c2-8f0c05d06519	first broker login	Actions taken after first broker login with identity provider account, which is not yet linked to any Keycloak account	21dfe33f-5923-4bfd-bc04-cf200e747656	basic-flow	t	t
b583b84e-5152-48f6-bfc3-566ae3a8fcc8	User creation or linking	Flow for the existing/non-existing user alternatives	21dfe33f-5923-4bfd-bc04-cf200e747656	basic-flow	f	t
2f967780-8d62-416c-b2c4-4072d44dc08e	Handle Existing Account	Handle what to do if there is existing account with same email/username like authenticated identity provider	21dfe33f-5923-4bfd-bc04-cf200e747656	basic-flow	f	t
52056be6-e28c-4361-9389-58937e3aef97	Account verification options	Method with which to verity the existing account	21dfe33f-5923-4bfd-bc04-cf200e747656	basic-flow	f	t
e4e3f108-5c38-45f9-92ad-79af7dcd778e	Verify Existing Account by Re-authentication	Reauthentication of existing account	21dfe33f-5923-4bfd-bc04-cf200e747656	basic-flow	f	t
f73cfdc9-6f33-4bdb-a6d4-dc428757289a	First broker login - Conditional OTP	Flow to determine if the OTP is required for the authentication	21dfe33f-5923-4bfd-bc04-cf200e747656	basic-flow	f	t
3fd1dcad-8892-49dd-9cfc-fa8a0cc40356	First Broker Login - Conditional Organization	Flow to determine if the authenticator that adds organization members is to be used	21dfe33f-5923-4bfd-bc04-cf200e747656	basic-flow	f	t
4c6d14b5-f912-473b-9037-bd4de57ac95f	saml ecp	SAML ECP Profile Authentication Flow	21dfe33f-5923-4bfd-bc04-cf200e747656	basic-flow	t	t
03c9b0c7-1b02-4b5b-93ca-d94f5fff38c6	docker auth	Used by Docker clients to authenticate against the IDP	21dfe33f-5923-4bfd-bc04-cf200e747656	basic-flow	t	t
\.


--
-- Data for Name: authenticator_config; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.authenticator_config (id, alias, realm_id) FROM stdin;
af98a68b-5df1-4215-a7ff-1ca9c8673df8	review profile config	5be18a3e-7181-4862-867b-45aff91b9b87
2e70c740-3a12-46a1-8b5a-88e04b80c6ba	create unique user config	5be18a3e-7181-4862-867b-45aff91b9b87
5d79c34d-7837-411d-b64c-89d5cfd58098	review profile config	21dfe33f-5923-4bfd-bc04-cf200e747656
037e8455-f731-4e71-9340-bcdbacb4053a	create unique user config	21dfe33f-5923-4bfd-bc04-cf200e747656
\.


--
-- Data for Name: authenticator_config_entry; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.authenticator_config_entry (authenticator_id, value, name) FROM stdin;
2e70c740-3a12-46a1-8b5a-88e04b80c6ba	false	require.password.update.after.registration
af98a68b-5df1-4215-a7ff-1ca9c8673df8	missing	update.profile.on.first.login
037e8455-f731-4e71-9340-bcdbacb4053a	false	require.password.update.after.registration
5d79c34d-7837-411d-b64c-89d5cfd58098	missing	update.profile.on.first.login
\.


--
-- Data for Name: broker_link; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.broker_link (identity_provider, storage_provider_id, realm_id, broker_user_id, broker_username, token, user_id) FROM stdin;
\.


--
-- Data for Name: client; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.client (id, enabled, full_scope_allowed, client_id, not_before, public_client, secret, base_url, bearer_only, management_url, surrogate_auth_required, realm_id, protocol, node_rereg_timeout, frontchannel_logout, consent_required, name, service_accounts_enabled, client_authenticator_type, root_url, description, registration_token, standard_flow_enabled, implicit_flow_enabled, direct_access_grants_enabled, always_display_in_console) FROM stdin;
58c02ea4-9114-4070-86ce-72fd450066cf	t	f	master-realm	0	f	\N	\N	t	\N	f	5be18a3e-7181-4862-867b-45aff91b9b87	\N	0	f	f	master Realm	f	client-secret	\N	\N	\N	t	f	f	f
d0dc1596-18e2-4ccc-bd5e-cc8a1b52db61	t	f	account	0	t	\N	/realms/master/account/	f	\N	f	5be18a3e-7181-4862-867b-45aff91b9b87	openid-connect	0	f	f	${client_account}	f	client-secret	${authBaseUrl}	\N	\N	t	f	f	f
250d1167-7f36-432a-96eb-492124c372b1	t	f	account-console	0	t	\N	/realms/master/account/	f	\N	f	5be18a3e-7181-4862-867b-45aff91b9b87	openid-connect	0	f	f	${client_account-console}	f	client-secret	${authBaseUrl}	\N	\N	t	f	f	f
89738f4a-9efa-482e-8c1e-3a5b2a1ac2a6	t	f	broker	0	f	\N	\N	t	\N	f	5be18a3e-7181-4862-867b-45aff91b9b87	openid-connect	0	f	f	${client_broker}	f	client-secret	\N	\N	\N	t	f	f	f
489d25cc-3b6e-49bc-b4d3-7ece35cf3eff	t	t	security-admin-console	0	t	\N	/admin/master/console/	f	\N	f	5be18a3e-7181-4862-867b-45aff91b9b87	openid-connect	0	f	f	${client_security-admin-console}	f	client-secret	${authAdminUrl}	\N	\N	t	f	f	f
50969b1b-7017-4956-b737-7f791fce4319	t	t	admin-cli	0	t	\N	\N	f	\N	f	5be18a3e-7181-4862-867b-45aff91b9b87	openid-connect	0	f	f	${client_admin-cli}	f	client-secret	\N	\N	\N	f	f	t	f
a21e795c-3dc5-4e25-9faf-13c6c3df2b02	t	f	local-realm	0	f	\N	\N	t	\N	f	5be18a3e-7181-4862-867b-45aff91b9b87	\N	0	f	f	local Realm	f	client-secret	\N	\N	\N	t	f	f	f
fc2f4568-b7af-409b-9647-d1632a32abf7	t	f	realm-management	0	f	\N	\N	t	\N	f	21dfe33f-5923-4bfd-bc04-cf200e747656	openid-connect	0	f	f	${client_realm-management}	f	client-secret	\N	\N	\N	t	f	f	f
e1fd0113-c702-4617-9068-7c9142d6b48b	t	f	account	0	t	\N	/realms/local/account/	f	\N	f	21dfe33f-5923-4bfd-bc04-cf200e747656	openid-connect	0	f	f	${client_account}	f	client-secret	${authBaseUrl}	\N	\N	t	f	f	f
9f5333a7-931d-4663-b07d-c89928cd6498	t	f	account-console	0	t	\N	/realms/local/account/	f	\N	f	21dfe33f-5923-4bfd-bc04-cf200e747656	openid-connect	0	f	f	${client_account-console}	f	client-secret	${authBaseUrl}	\N	\N	t	f	f	f
23ea499c-7892-4f61-9cd3-9fbe4c9f493c	t	f	broker	0	f	\N	\N	t	\N	f	21dfe33f-5923-4bfd-bc04-cf200e747656	openid-connect	0	f	f	${client_broker}	f	client-secret	\N	\N	\N	t	f	f	f
94df3d2f-7a99-4794-92f9-c879ceea36a0	t	t	security-admin-console	0	t	\N	/admin/local/console/	f	\N	f	21dfe33f-5923-4bfd-bc04-cf200e747656	openid-connect	0	f	f	${client_security-admin-console}	f	client-secret	${authAdminUrl}	\N	\N	t	f	f	f
8138fe45-ca77-4ca4-9f3f-a94c91a84aaf	t	t	admin-cli	0	t	\N	\N	f	\N	f	21dfe33f-5923-4bfd-bc04-cf200e747656	openid-connect	0	f	f	${client_admin-cli}	f	client-secret	\N	\N	\N	f	f	t	f
40f8f713-e1c4-4e9d-a804-2ec22fb3d118	t	t	local-client	0	f	q0Mgf9lhV6TBvnLxZljqOsrFHz4Nj9RY		f	http://localhost:8888	f	5be18a3e-7181-4862-867b-45aff91b9b87	openid-connect	-1	t	f		t	client-secret	http://localhost:8888		\N	t	f	t	f
ab4df486-dff6-488a-aa26-56cccddaf5fc	t	t	local-client	0	f	nZUMlOQZufa5ljWW5hHXOtGKLn0mpTkN		f	http://localhost:8888	f	21dfe33f-5923-4bfd-bc04-cf200e747656	openid-connect	-1	t	f		t	client-secret	http://localhost:8888		\N	t	f	t	f
\.


--
-- Data for Name: client_attributes; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.client_attributes (client_id, name, value) FROM stdin;
d0dc1596-18e2-4ccc-bd5e-cc8a1b52db61	post.logout.redirect.uris	+
250d1167-7f36-432a-96eb-492124c372b1	post.logout.redirect.uris	+
250d1167-7f36-432a-96eb-492124c372b1	pkce.code.challenge.method	S256
489d25cc-3b6e-49bc-b4d3-7ece35cf3eff	post.logout.redirect.uris	+
489d25cc-3b6e-49bc-b4d3-7ece35cf3eff	pkce.code.challenge.method	S256
489d25cc-3b6e-49bc-b4d3-7ece35cf3eff	client.use.lightweight.access.token.enabled	true
50969b1b-7017-4956-b737-7f791fce4319	client.use.lightweight.access.token.enabled	true
e1fd0113-c702-4617-9068-7c9142d6b48b	post.logout.redirect.uris	+
9f5333a7-931d-4663-b07d-c89928cd6498	post.logout.redirect.uris	+
9f5333a7-931d-4663-b07d-c89928cd6498	pkce.code.challenge.method	S256
94df3d2f-7a99-4794-92f9-c879ceea36a0	post.logout.redirect.uris	+
94df3d2f-7a99-4794-92f9-c879ceea36a0	pkce.code.challenge.method	S256
94df3d2f-7a99-4794-92f9-c879ceea36a0	client.use.lightweight.access.token.enabled	true
8138fe45-ca77-4ca4-9f3f-a94c91a84aaf	client.use.lightweight.access.token.enabled	true
40f8f713-e1c4-4e9d-a804-2ec22fb3d118	client.secret.creation.time	1762554610
40f8f713-e1c4-4e9d-a804-2ec22fb3d118	oauth2.device.authorization.grant.enabled	false
40f8f713-e1c4-4e9d-a804-2ec22fb3d118	oidc.ciba.grant.enabled	false
40f8f713-e1c4-4e9d-a804-2ec22fb3d118	backchannel.logout.session.required	true
40f8f713-e1c4-4e9d-a804-2ec22fb3d118	backchannel.logout.revoke.offline.tokens	false
ab4df486-dff6-488a-aa26-56cccddaf5fc	client.secret.creation.time	1762558445
ab4df486-dff6-488a-aa26-56cccddaf5fc	oauth2.device.authorization.grant.enabled	false
ab4df486-dff6-488a-aa26-56cccddaf5fc	oidc.ciba.grant.enabled	false
ab4df486-dff6-488a-aa26-56cccddaf5fc	post.logout.redirect.uris	http://localhost:8888/login/oauth2/code/keycloak
ab4df486-dff6-488a-aa26-56cccddaf5fc	backchannel.logout.session.required	true
ab4df486-dff6-488a-aa26-56cccddaf5fc	backchannel.logout.revoke.offline.tokens	false
\.


--
-- Data for Name: client_auth_flow_bindings; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.client_auth_flow_bindings (client_id, flow_id, binding_name) FROM stdin;
\.


--
-- Data for Name: client_initial_access; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.client_initial_access (id, realm_id, "timestamp", expiration, count, remaining_count) FROM stdin;
\.


--
-- Data for Name: client_node_registrations; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.client_node_registrations (client_id, value, name) FROM stdin;
\.


--
-- Data for Name: client_scope; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.client_scope (id, name, realm_id, description, protocol) FROM stdin;
461e2807-85fa-4147-b6cc-7c72852a2430	offline_access	5be18a3e-7181-4862-867b-45aff91b9b87	OpenID Connect built-in scope: offline_access	openid-connect
8c914f2e-64ad-41b1-857f-8a8bf62ed0b1	role_list	5be18a3e-7181-4862-867b-45aff91b9b87	SAML role list	saml
bf63aca5-a028-4427-afec-679fc54e78ba	saml_organization	5be18a3e-7181-4862-867b-45aff91b9b87	Organization Membership	saml
75cee988-908f-4f5c-9bcc-072208c81168	profile	5be18a3e-7181-4862-867b-45aff91b9b87	OpenID Connect built-in scope: profile	openid-connect
9d4c6a24-8c01-4658-b3f5-da010d0a8f5f	email	5be18a3e-7181-4862-867b-45aff91b9b87	OpenID Connect built-in scope: email	openid-connect
1038a83e-ad8a-4643-a4fd-07e2cde170f4	address	5be18a3e-7181-4862-867b-45aff91b9b87	OpenID Connect built-in scope: address	openid-connect
95506dce-4939-4d6a-8700-95d1cedead31	phone	5be18a3e-7181-4862-867b-45aff91b9b87	OpenID Connect built-in scope: phone	openid-connect
d8ef9497-8cf0-4560-824a-4c9329319677	roles	5be18a3e-7181-4862-867b-45aff91b9b87	OpenID Connect scope for add user roles to the access token	openid-connect
dc5d8147-1c9b-4dea-856e-6a701be77a28	web-origins	5be18a3e-7181-4862-867b-45aff91b9b87	OpenID Connect scope for add allowed web origins to the access token	openid-connect
4027eeb6-c7ad-4116-904b-a2df4e36b9e8	microprofile-jwt	5be18a3e-7181-4862-867b-45aff91b9b87	Microprofile - JWT built-in scope	openid-connect
3f8efb2a-e473-45eb-be11-7440abc689ac	acr	5be18a3e-7181-4862-867b-45aff91b9b87	OpenID Connect scope for add acr (authentication context class reference) to the token	openid-connect
7ae1f834-5642-46dd-8e8c-15e04b03855b	basic	5be18a3e-7181-4862-867b-45aff91b9b87	OpenID Connect scope for add all basic claims to the token	openid-connect
ed5212a6-310a-4582-9c92-3610bf722f23	organization	5be18a3e-7181-4862-867b-45aff91b9b87	Additional claims about the organization a subject belongs to	openid-connect
7ccd275b-86ef-43e6-b48e-bb0950ef2196	offline_access	21dfe33f-5923-4bfd-bc04-cf200e747656	OpenID Connect built-in scope: offline_access	openid-connect
7af22446-a644-47ee-b4ff-50ae92fa75b5	role_list	21dfe33f-5923-4bfd-bc04-cf200e747656	SAML role list	saml
4f907d9a-50f0-4f21-a8bc-abba39a00872	saml_organization	21dfe33f-5923-4bfd-bc04-cf200e747656	Organization Membership	saml
a4ed44cb-bcd9-4403-bdf6-ff361131c239	profile	21dfe33f-5923-4bfd-bc04-cf200e747656	OpenID Connect built-in scope: profile	openid-connect
1b300f54-3ac9-44c4-ad0b-414957f47ebc	email	21dfe33f-5923-4bfd-bc04-cf200e747656	OpenID Connect built-in scope: email	openid-connect
6bc2853a-a28e-44de-9036-0e505be14d79	address	21dfe33f-5923-4bfd-bc04-cf200e747656	OpenID Connect built-in scope: address	openid-connect
b8041d7f-a6a0-4d56-aad4-33750056ee31	phone	21dfe33f-5923-4bfd-bc04-cf200e747656	OpenID Connect built-in scope: phone	openid-connect
e47d3371-e4be-45f3-89aa-4b74f1f87832	roles	21dfe33f-5923-4bfd-bc04-cf200e747656	OpenID Connect scope for add user roles to the access token	openid-connect
70c49995-ea6d-498b-bba4-7b4a51b46fe9	web-origins	21dfe33f-5923-4bfd-bc04-cf200e747656	OpenID Connect scope for add allowed web origins to the access token	openid-connect
cc0c3d1c-4e90-47aa-aae0-44f1dcf89a15	microprofile-jwt	21dfe33f-5923-4bfd-bc04-cf200e747656	Microprofile - JWT built-in scope	openid-connect
f3951ff7-42a3-4fd7-9219-c8aecfb52169	acr	21dfe33f-5923-4bfd-bc04-cf200e747656	OpenID Connect scope for add acr (authentication context class reference) to the token	openid-connect
a8710cae-609f-4d07-b2e8-bf878bb356d3	basic	21dfe33f-5923-4bfd-bc04-cf200e747656	OpenID Connect scope for add all basic claims to the token	openid-connect
92d3c51f-da77-4ec0-a58a-3cf9a81d8bd1	organization	21dfe33f-5923-4bfd-bc04-cf200e747656	Additional claims about the organization a subject belongs to	openid-connect
\.


--
-- Data for Name: client_scope_attributes; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.client_scope_attributes (scope_id, value, name) FROM stdin;
461e2807-85fa-4147-b6cc-7c72852a2430	true	display.on.consent.screen
461e2807-85fa-4147-b6cc-7c72852a2430	${offlineAccessScopeConsentText}	consent.screen.text
8c914f2e-64ad-41b1-857f-8a8bf62ed0b1	true	display.on.consent.screen
8c914f2e-64ad-41b1-857f-8a8bf62ed0b1	${samlRoleListScopeConsentText}	consent.screen.text
bf63aca5-a028-4427-afec-679fc54e78ba	false	display.on.consent.screen
75cee988-908f-4f5c-9bcc-072208c81168	true	display.on.consent.screen
75cee988-908f-4f5c-9bcc-072208c81168	${profileScopeConsentText}	consent.screen.text
75cee988-908f-4f5c-9bcc-072208c81168	true	include.in.token.scope
9d4c6a24-8c01-4658-b3f5-da010d0a8f5f	true	display.on.consent.screen
9d4c6a24-8c01-4658-b3f5-da010d0a8f5f	${emailScopeConsentText}	consent.screen.text
9d4c6a24-8c01-4658-b3f5-da010d0a8f5f	true	include.in.token.scope
1038a83e-ad8a-4643-a4fd-07e2cde170f4	true	display.on.consent.screen
1038a83e-ad8a-4643-a4fd-07e2cde170f4	${addressScopeConsentText}	consent.screen.text
1038a83e-ad8a-4643-a4fd-07e2cde170f4	true	include.in.token.scope
95506dce-4939-4d6a-8700-95d1cedead31	true	display.on.consent.screen
95506dce-4939-4d6a-8700-95d1cedead31	${phoneScopeConsentText}	consent.screen.text
95506dce-4939-4d6a-8700-95d1cedead31	true	include.in.token.scope
d8ef9497-8cf0-4560-824a-4c9329319677	true	display.on.consent.screen
d8ef9497-8cf0-4560-824a-4c9329319677	${rolesScopeConsentText}	consent.screen.text
d8ef9497-8cf0-4560-824a-4c9329319677	false	include.in.token.scope
dc5d8147-1c9b-4dea-856e-6a701be77a28	false	display.on.consent.screen
dc5d8147-1c9b-4dea-856e-6a701be77a28		consent.screen.text
dc5d8147-1c9b-4dea-856e-6a701be77a28	false	include.in.token.scope
4027eeb6-c7ad-4116-904b-a2df4e36b9e8	false	display.on.consent.screen
4027eeb6-c7ad-4116-904b-a2df4e36b9e8	true	include.in.token.scope
3f8efb2a-e473-45eb-be11-7440abc689ac	false	display.on.consent.screen
3f8efb2a-e473-45eb-be11-7440abc689ac	false	include.in.token.scope
7ae1f834-5642-46dd-8e8c-15e04b03855b	false	display.on.consent.screen
7ae1f834-5642-46dd-8e8c-15e04b03855b	false	include.in.token.scope
ed5212a6-310a-4582-9c92-3610bf722f23	true	display.on.consent.screen
ed5212a6-310a-4582-9c92-3610bf722f23	${organizationScopeConsentText}	consent.screen.text
ed5212a6-310a-4582-9c92-3610bf722f23	true	include.in.token.scope
7ccd275b-86ef-43e6-b48e-bb0950ef2196	true	display.on.consent.screen
7ccd275b-86ef-43e6-b48e-bb0950ef2196	${offlineAccessScopeConsentText}	consent.screen.text
7af22446-a644-47ee-b4ff-50ae92fa75b5	true	display.on.consent.screen
7af22446-a644-47ee-b4ff-50ae92fa75b5	${samlRoleListScopeConsentText}	consent.screen.text
4f907d9a-50f0-4f21-a8bc-abba39a00872	false	display.on.consent.screen
a4ed44cb-bcd9-4403-bdf6-ff361131c239	true	display.on.consent.screen
a4ed44cb-bcd9-4403-bdf6-ff361131c239	${profileScopeConsentText}	consent.screen.text
a4ed44cb-bcd9-4403-bdf6-ff361131c239	true	include.in.token.scope
1b300f54-3ac9-44c4-ad0b-414957f47ebc	true	display.on.consent.screen
1b300f54-3ac9-44c4-ad0b-414957f47ebc	${emailScopeConsentText}	consent.screen.text
1b300f54-3ac9-44c4-ad0b-414957f47ebc	true	include.in.token.scope
6bc2853a-a28e-44de-9036-0e505be14d79	true	display.on.consent.screen
6bc2853a-a28e-44de-9036-0e505be14d79	${addressScopeConsentText}	consent.screen.text
6bc2853a-a28e-44de-9036-0e505be14d79	true	include.in.token.scope
b8041d7f-a6a0-4d56-aad4-33750056ee31	true	display.on.consent.screen
b8041d7f-a6a0-4d56-aad4-33750056ee31	${phoneScopeConsentText}	consent.screen.text
b8041d7f-a6a0-4d56-aad4-33750056ee31	true	include.in.token.scope
e47d3371-e4be-45f3-89aa-4b74f1f87832	true	display.on.consent.screen
e47d3371-e4be-45f3-89aa-4b74f1f87832	${rolesScopeConsentText}	consent.screen.text
e47d3371-e4be-45f3-89aa-4b74f1f87832	false	include.in.token.scope
70c49995-ea6d-498b-bba4-7b4a51b46fe9	false	display.on.consent.screen
70c49995-ea6d-498b-bba4-7b4a51b46fe9		consent.screen.text
70c49995-ea6d-498b-bba4-7b4a51b46fe9	false	include.in.token.scope
cc0c3d1c-4e90-47aa-aae0-44f1dcf89a15	false	display.on.consent.screen
cc0c3d1c-4e90-47aa-aae0-44f1dcf89a15	true	include.in.token.scope
f3951ff7-42a3-4fd7-9219-c8aecfb52169	false	display.on.consent.screen
f3951ff7-42a3-4fd7-9219-c8aecfb52169	false	include.in.token.scope
a8710cae-609f-4d07-b2e8-bf878bb356d3	false	display.on.consent.screen
a8710cae-609f-4d07-b2e8-bf878bb356d3	false	include.in.token.scope
92d3c51f-da77-4ec0-a58a-3cf9a81d8bd1	true	display.on.consent.screen
92d3c51f-da77-4ec0-a58a-3cf9a81d8bd1	${organizationScopeConsentText}	consent.screen.text
92d3c51f-da77-4ec0-a58a-3cf9a81d8bd1	true	include.in.token.scope
\.


--
-- Data for Name: client_scope_client; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.client_scope_client (client_id, scope_id, default_scope) FROM stdin;
d0dc1596-18e2-4ccc-bd5e-cc8a1b52db61	75cee988-908f-4f5c-9bcc-072208c81168	t
d0dc1596-18e2-4ccc-bd5e-cc8a1b52db61	d8ef9497-8cf0-4560-824a-4c9329319677	t
d0dc1596-18e2-4ccc-bd5e-cc8a1b52db61	7ae1f834-5642-46dd-8e8c-15e04b03855b	t
d0dc1596-18e2-4ccc-bd5e-cc8a1b52db61	3f8efb2a-e473-45eb-be11-7440abc689ac	t
d0dc1596-18e2-4ccc-bd5e-cc8a1b52db61	9d4c6a24-8c01-4658-b3f5-da010d0a8f5f	t
d0dc1596-18e2-4ccc-bd5e-cc8a1b52db61	dc5d8147-1c9b-4dea-856e-6a701be77a28	t
d0dc1596-18e2-4ccc-bd5e-cc8a1b52db61	461e2807-85fa-4147-b6cc-7c72852a2430	f
d0dc1596-18e2-4ccc-bd5e-cc8a1b52db61	ed5212a6-310a-4582-9c92-3610bf722f23	f
d0dc1596-18e2-4ccc-bd5e-cc8a1b52db61	95506dce-4939-4d6a-8700-95d1cedead31	f
d0dc1596-18e2-4ccc-bd5e-cc8a1b52db61	1038a83e-ad8a-4643-a4fd-07e2cde170f4	f
d0dc1596-18e2-4ccc-bd5e-cc8a1b52db61	4027eeb6-c7ad-4116-904b-a2df4e36b9e8	f
250d1167-7f36-432a-96eb-492124c372b1	75cee988-908f-4f5c-9bcc-072208c81168	t
250d1167-7f36-432a-96eb-492124c372b1	d8ef9497-8cf0-4560-824a-4c9329319677	t
250d1167-7f36-432a-96eb-492124c372b1	7ae1f834-5642-46dd-8e8c-15e04b03855b	t
250d1167-7f36-432a-96eb-492124c372b1	3f8efb2a-e473-45eb-be11-7440abc689ac	t
250d1167-7f36-432a-96eb-492124c372b1	9d4c6a24-8c01-4658-b3f5-da010d0a8f5f	t
250d1167-7f36-432a-96eb-492124c372b1	dc5d8147-1c9b-4dea-856e-6a701be77a28	t
250d1167-7f36-432a-96eb-492124c372b1	461e2807-85fa-4147-b6cc-7c72852a2430	f
250d1167-7f36-432a-96eb-492124c372b1	ed5212a6-310a-4582-9c92-3610bf722f23	f
250d1167-7f36-432a-96eb-492124c372b1	95506dce-4939-4d6a-8700-95d1cedead31	f
250d1167-7f36-432a-96eb-492124c372b1	1038a83e-ad8a-4643-a4fd-07e2cde170f4	f
250d1167-7f36-432a-96eb-492124c372b1	4027eeb6-c7ad-4116-904b-a2df4e36b9e8	f
50969b1b-7017-4956-b737-7f791fce4319	75cee988-908f-4f5c-9bcc-072208c81168	t
50969b1b-7017-4956-b737-7f791fce4319	d8ef9497-8cf0-4560-824a-4c9329319677	t
50969b1b-7017-4956-b737-7f791fce4319	7ae1f834-5642-46dd-8e8c-15e04b03855b	t
50969b1b-7017-4956-b737-7f791fce4319	3f8efb2a-e473-45eb-be11-7440abc689ac	t
50969b1b-7017-4956-b737-7f791fce4319	9d4c6a24-8c01-4658-b3f5-da010d0a8f5f	t
50969b1b-7017-4956-b737-7f791fce4319	dc5d8147-1c9b-4dea-856e-6a701be77a28	t
50969b1b-7017-4956-b737-7f791fce4319	461e2807-85fa-4147-b6cc-7c72852a2430	f
50969b1b-7017-4956-b737-7f791fce4319	ed5212a6-310a-4582-9c92-3610bf722f23	f
50969b1b-7017-4956-b737-7f791fce4319	95506dce-4939-4d6a-8700-95d1cedead31	f
50969b1b-7017-4956-b737-7f791fce4319	1038a83e-ad8a-4643-a4fd-07e2cde170f4	f
50969b1b-7017-4956-b737-7f791fce4319	4027eeb6-c7ad-4116-904b-a2df4e36b9e8	f
89738f4a-9efa-482e-8c1e-3a5b2a1ac2a6	75cee988-908f-4f5c-9bcc-072208c81168	t
89738f4a-9efa-482e-8c1e-3a5b2a1ac2a6	d8ef9497-8cf0-4560-824a-4c9329319677	t
89738f4a-9efa-482e-8c1e-3a5b2a1ac2a6	7ae1f834-5642-46dd-8e8c-15e04b03855b	t
89738f4a-9efa-482e-8c1e-3a5b2a1ac2a6	3f8efb2a-e473-45eb-be11-7440abc689ac	t
89738f4a-9efa-482e-8c1e-3a5b2a1ac2a6	9d4c6a24-8c01-4658-b3f5-da010d0a8f5f	t
89738f4a-9efa-482e-8c1e-3a5b2a1ac2a6	dc5d8147-1c9b-4dea-856e-6a701be77a28	t
89738f4a-9efa-482e-8c1e-3a5b2a1ac2a6	461e2807-85fa-4147-b6cc-7c72852a2430	f
89738f4a-9efa-482e-8c1e-3a5b2a1ac2a6	ed5212a6-310a-4582-9c92-3610bf722f23	f
89738f4a-9efa-482e-8c1e-3a5b2a1ac2a6	95506dce-4939-4d6a-8700-95d1cedead31	f
89738f4a-9efa-482e-8c1e-3a5b2a1ac2a6	1038a83e-ad8a-4643-a4fd-07e2cde170f4	f
89738f4a-9efa-482e-8c1e-3a5b2a1ac2a6	4027eeb6-c7ad-4116-904b-a2df4e36b9e8	f
58c02ea4-9114-4070-86ce-72fd450066cf	75cee988-908f-4f5c-9bcc-072208c81168	t
58c02ea4-9114-4070-86ce-72fd450066cf	d8ef9497-8cf0-4560-824a-4c9329319677	t
58c02ea4-9114-4070-86ce-72fd450066cf	7ae1f834-5642-46dd-8e8c-15e04b03855b	t
58c02ea4-9114-4070-86ce-72fd450066cf	3f8efb2a-e473-45eb-be11-7440abc689ac	t
58c02ea4-9114-4070-86ce-72fd450066cf	9d4c6a24-8c01-4658-b3f5-da010d0a8f5f	t
58c02ea4-9114-4070-86ce-72fd450066cf	dc5d8147-1c9b-4dea-856e-6a701be77a28	t
58c02ea4-9114-4070-86ce-72fd450066cf	461e2807-85fa-4147-b6cc-7c72852a2430	f
58c02ea4-9114-4070-86ce-72fd450066cf	ed5212a6-310a-4582-9c92-3610bf722f23	f
58c02ea4-9114-4070-86ce-72fd450066cf	95506dce-4939-4d6a-8700-95d1cedead31	f
58c02ea4-9114-4070-86ce-72fd450066cf	1038a83e-ad8a-4643-a4fd-07e2cde170f4	f
58c02ea4-9114-4070-86ce-72fd450066cf	4027eeb6-c7ad-4116-904b-a2df4e36b9e8	f
489d25cc-3b6e-49bc-b4d3-7ece35cf3eff	75cee988-908f-4f5c-9bcc-072208c81168	t
489d25cc-3b6e-49bc-b4d3-7ece35cf3eff	d8ef9497-8cf0-4560-824a-4c9329319677	t
489d25cc-3b6e-49bc-b4d3-7ece35cf3eff	7ae1f834-5642-46dd-8e8c-15e04b03855b	t
489d25cc-3b6e-49bc-b4d3-7ece35cf3eff	3f8efb2a-e473-45eb-be11-7440abc689ac	t
489d25cc-3b6e-49bc-b4d3-7ece35cf3eff	9d4c6a24-8c01-4658-b3f5-da010d0a8f5f	t
489d25cc-3b6e-49bc-b4d3-7ece35cf3eff	dc5d8147-1c9b-4dea-856e-6a701be77a28	t
489d25cc-3b6e-49bc-b4d3-7ece35cf3eff	461e2807-85fa-4147-b6cc-7c72852a2430	f
489d25cc-3b6e-49bc-b4d3-7ece35cf3eff	ed5212a6-310a-4582-9c92-3610bf722f23	f
489d25cc-3b6e-49bc-b4d3-7ece35cf3eff	95506dce-4939-4d6a-8700-95d1cedead31	f
489d25cc-3b6e-49bc-b4d3-7ece35cf3eff	1038a83e-ad8a-4643-a4fd-07e2cde170f4	f
489d25cc-3b6e-49bc-b4d3-7ece35cf3eff	4027eeb6-c7ad-4116-904b-a2df4e36b9e8	f
e1fd0113-c702-4617-9068-7c9142d6b48b	f3951ff7-42a3-4fd7-9219-c8aecfb52169	t
e1fd0113-c702-4617-9068-7c9142d6b48b	1b300f54-3ac9-44c4-ad0b-414957f47ebc	t
e1fd0113-c702-4617-9068-7c9142d6b48b	a4ed44cb-bcd9-4403-bdf6-ff361131c239	t
e1fd0113-c702-4617-9068-7c9142d6b48b	70c49995-ea6d-498b-bba4-7b4a51b46fe9	t
e1fd0113-c702-4617-9068-7c9142d6b48b	a8710cae-609f-4d07-b2e8-bf878bb356d3	t
e1fd0113-c702-4617-9068-7c9142d6b48b	e47d3371-e4be-45f3-89aa-4b74f1f87832	t
e1fd0113-c702-4617-9068-7c9142d6b48b	92d3c51f-da77-4ec0-a58a-3cf9a81d8bd1	f
e1fd0113-c702-4617-9068-7c9142d6b48b	cc0c3d1c-4e90-47aa-aae0-44f1dcf89a15	f
e1fd0113-c702-4617-9068-7c9142d6b48b	6bc2853a-a28e-44de-9036-0e505be14d79	f
e1fd0113-c702-4617-9068-7c9142d6b48b	7ccd275b-86ef-43e6-b48e-bb0950ef2196	f
e1fd0113-c702-4617-9068-7c9142d6b48b	b8041d7f-a6a0-4d56-aad4-33750056ee31	f
9f5333a7-931d-4663-b07d-c89928cd6498	f3951ff7-42a3-4fd7-9219-c8aecfb52169	t
9f5333a7-931d-4663-b07d-c89928cd6498	1b300f54-3ac9-44c4-ad0b-414957f47ebc	t
9f5333a7-931d-4663-b07d-c89928cd6498	a4ed44cb-bcd9-4403-bdf6-ff361131c239	t
9f5333a7-931d-4663-b07d-c89928cd6498	70c49995-ea6d-498b-bba4-7b4a51b46fe9	t
9f5333a7-931d-4663-b07d-c89928cd6498	a8710cae-609f-4d07-b2e8-bf878bb356d3	t
9f5333a7-931d-4663-b07d-c89928cd6498	e47d3371-e4be-45f3-89aa-4b74f1f87832	t
9f5333a7-931d-4663-b07d-c89928cd6498	92d3c51f-da77-4ec0-a58a-3cf9a81d8bd1	f
9f5333a7-931d-4663-b07d-c89928cd6498	cc0c3d1c-4e90-47aa-aae0-44f1dcf89a15	f
9f5333a7-931d-4663-b07d-c89928cd6498	6bc2853a-a28e-44de-9036-0e505be14d79	f
9f5333a7-931d-4663-b07d-c89928cd6498	7ccd275b-86ef-43e6-b48e-bb0950ef2196	f
9f5333a7-931d-4663-b07d-c89928cd6498	b8041d7f-a6a0-4d56-aad4-33750056ee31	f
8138fe45-ca77-4ca4-9f3f-a94c91a84aaf	f3951ff7-42a3-4fd7-9219-c8aecfb52169	t
8138fe45-ca77-4ca4-9f3f-a94c91a84aaf	1b300f54-3ac9-44c4-ad0b-414957f47ebc	t
8138fe45-ca77-4ca4-9f3f-a94c91a84aaf	a4ed44cb-bcd9-4403-bdf6-ff361131c239	t
8138fe45-ca77-4ca4-9f3f-a94c91a84aaf	70c49995-ea6d-498b-bba4-7b4a51b46fe9	t
8138fe45-ca77-4ca4-9f3f-a94c91a84aaf	a8710cae-609f-4d07-b2e8-bf878bb356d3	t
8138fe45-ca77-4ca4-9f3f-a94c91a84aaf	e47d3371-e4be-45f3-89aa-4b74f1f87832	t
8138fe45-ca77-4ca4-9f3f-a94c91a84aaf	92d3c51f-da77-4ec0-a58a-3cf9a81d8bd1	f
8138fe45-ca77-4ca4-9f3f-a94c91a84aaf	cc0c3d1c-4e90-47aa-aae0-44f1dcf89a15	f
8138fe45-ca77-4ca4-9f3f-a94c91a84aaf	6bc2853a-a28e-44de-9036-0e505be14d79	f
8138fe45-ca77-4ca4-9f3f-a94c91a84aaf	7ccd275b-86ef-43e6-b48e-bb0950ef2196	f
8138fe45-ca77-4ca4-9f3f-a94c91a84aaf	b8041d7f-a6a0-4d56-aad4-33750056ee31	f
23ea499c-7892-4f61-9cd3-9fbe4c9f493c	f3951ff7-42a3-4fd7-9219-c8aecfb52169	t
23ea499c-7892-4f61-9cd3-9fbe4c9f493c	1b300f54-3ac9-44c4-ad0b-414957f47ebc	t
23ea499c-7892-4f61-9cd3-9fbe4c9f493c	a4ed44cb-bcd9-4403-bdf6-ff361131c239	t
23ea499c-7892-4f61-9cd3-9fbe4c9f493c	70c49995-ea6d-498b-bba4-7b4a51b46fe9	t
23ea499c-7892-4f61-9cd3-9fbe4c9f493c	a8710cae-609f-4d07-b2e8-bf878bb356d3	t
23ea499c-7892-4f61-9cd3-9fbe4c9f493c	e47d3371-e4be-45f3-89aa-4b74f1f87832	t
23ea499c-7892-4f61-9cd3-9fbe4c9f493c	92d3c51f-da77-4ec0-a58a-3cf9a81d8bd1	f
23ea499c-7892-4f61-9cd3-9fbe4c9f493c	cc0c3d1c-4e90-47aa-aae0-44f1dcf89a15	f
23ea499c-7892-4f61-9cd3-9fbe4c9f493c	6bc2853a-a28e-44de-9036-0e505be14d79	f
23ea499c-7892-4f61-9cd3-9fbe4c9f493c	7ccd275b-86ef-43e6-b48e-bb0950ef2196	f
23ea499c-7892-4f61-9cd3-9fbe4c9f493c	b8041d7f-a6a0-4d56-aad4-33750056ee31	f
fc2f4568-b7af-409b-9647-d1632a32abf7	f3951ff7-42a3-4fd7-9219-c8aecfb52169	t
fc2f4568-b7af-409b-9647-d1632a32abf7	1b300f54-3ac9-44c4-ad0b-414957f47ebc	t
fc2f4568-b7af-409b-9647-d1632a32abf7	a4ed44cb-bcd9-4403-bdf6-ff361131c239	t
fc2f4568-b7af-409b-9647-d1632a32abf7	70c49995-ea6d-498b-bba4-7b4a51b46fe9	t
fc2f4568-b7af-409b-9647-d1632a32abf7	a8710cae-609f-4d07-b2e8-bf878bb356d3	t
fc2f4568-b7af-409b-9647-d1632a32abf7	e47d3371-e4be-45f3-89aa-4b74f1f87832	t
fc2f4568-b7af-409b-9647-d1632a32abf7	92d3c51f-da77-4ec0-a58a-3cf9a81d8bd1	f
fc2f4568-b7af-409b-9647-d1632a32abf7	cc0c3d1c-4e90-47aa-aae0-44f1dcf89a15	f
fc2f4568-b7af-409b-9647-d1632a32abf7	6bc2853a-a28e-44de-9036-0e505be14d79	f
fc2f4568-b7af-409b-9647-d1632a32abf7	7ccd275b-86ef-43e6-b48e-bb0950ef2196	f
fc2f4568-b7af-409b-9647-d1632a32abf7	b8041d7f-a6a0-4d56-aad4-33750056ee31	f
94df3d2f-7a99-4794-92f9-c879ceea36a0	f3951ff7-42a3-4fd7-9219-c8aecfb52169	t
94df3d2f-7a99-4794-92f9-c879ceea36a0	1b300f54-3ac9-44c4-ad0b-414957f47ebc	t
94df3d2f-7a99-4794-92f9-c879ceea36a0	a4ed44cb-bcd9-4403-bdf6-ff361131c239	t
94df3d2f-7a99-4794-92f9-c879ceea36a0	70c49995-ea6d-498b-bba4-7b4a51b46fe9	t
94df3d2f-7a99-4794-92f9-c879ceea36a0	a8710cae-609f-4d07-b2e8-bf878bb356d3	t
94df3d2f-7a99-4794-92f9-c879ceea36a0	e47d3371-e4be-45f3-89aa-4b74f1f87832	t
94df3d2f-7a99-4794-92f9-c879ceea36a0	92d3c51f-da77-4ec0-a58a-3cf9a81d8bd1	f
94df3d2f-7a99-4794-92f9-c879ceea36a0	cc0c3d1c-4e90-47aa-aae0-44f1dcf89a15	f
94df3d2f-7a99-4794-92f9-c879ceea36a0	6bc2853a-a28e-44de-9036-0e505be14d79	f
94df3d2f-7a99-4794-92f9-c879ceea36a0	7ccd275b-86ef-43e6-b48e-bb0950ef2196	f
94df3d2f-7a99-4794-92f9-c879ceea36a0	b8041d7f-a6a0-4d56-aad4-33750056ee31	f
40f8f713-e1c4-4e9d-a804-2ec22fb3d118	75cee988-908f-4f5c-9bcc-072208c81168	t
40f8f713-e1c4-4e9d-a804-2ec22fb3d118	d8ef9497-8cf0-4560-824a-4c9329319677	t
40f8f713-e1c4-4e9d-a804-2ec22fb3d118	7ae1f834-5642-46dd-8e8c-15e04b03855b	t
40f8f713-e1c4-4e9d-a804-2ec22fb3d118	3f8efb2a-e473-45eb-be11-7440abc689ac	t
40f8f713-e1c4-4e9d-a804-2ec22fb3d118	9d4c6a24-8c01-4658-b3f5-da010d0a8f5f	t
40f8f713-e1c4-4e9d-a804-2ec22fb3d118	dc5d8147-1c9b-4dea-856e-6a701be77a28	t
40f8f713-e1c4-4e9d-a804-2ec22fb3d118	461e2807-85fa-4147-b6cc-7c72852a2430	f
40f8f713-e1c4-4e9d-a804-2ec22fb3d118	ed5212a6-310a-4582-9c92-3610bf722f23	f
40f8f713-e1c4-4e9d-a804-2ec22fb3d118	95506dce-4939-4d6a-8700-95d1cedead31	f
40f8f713-e1c4-4e9d-a804-2ec22fb3d118	1038a83e-ad8a-4643-a4fd-07e2cde170f4	f
40f8f713-e1c4-4e9d-a804-2ec22fb3d118	4027eeb6-c7ad-4116-904b-a2df4e36b9e8	f
ab4df486-dff6-488a-aa26-56cccddaf5fc	f3951ff7-42a3-4fd7-9219-c8aecfb52169	t
ab4df486-dff6-488a-aa26-56cccddaf5fc	1b300f54-3ac9-44c4-ad0b-414957f47ebc	t
ab4df486-dff6-488a-aa26-56cccddaf5fc	a4ed44cb-bcd9-4403-bdf6-ff361131c239	t
ab4df486-dff6-488a-aa26-56cccddaf5fc	70c49995-ea6d-498b-bba4-7b4a51b46fe9	t
ab4df486-dff6-488a-aa26-56cccddaf5fc	a8710cae-609f-4d07-b2e8-bf878bb356d3	t
ab4df486-dff6-488a-aa26-56cccddaf5fc	e47d3371-e4be-45f3-89aa-4b74f1f87832	t
ab4df486-dff6-488a-aa26-56cccddaf5fc	92d3c51f-da77-4ec0-a58a-3cf9a81d8bd1	f
ab4df486-dff6-488a-aa26-56cccddaf5fc	cc0c3d1c-4e90-47aa-aae0-44f1dcf89a15	f
ab4df486-dff6-488a-aa26-56cccddaf5fc	6bc2853a-a28e-44de-9036-0e505be14d79	f
ab4df486-dff6-488a-aa26-56cccddaf5fc	7ccd275b-86ef-43e6-b48e-bb0950ef2196	f
ab4df486-dff6-488a-aa26-56cccddaf5fc	b8041d7f-a6a0-4d56-aad4-33750056ee31	f
\.


--
-- Data for Name: client_scope_role_mapping; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.client_scope_role_mapping (scope_id, role_id) FROM stdin;
461e2807-85fa-4147-b6cc-7c72852a2430	e23e71ce-b6c5-4aa7-9077-bf1cb8878745
7ccd275b-86ef-43e6-b48e-bb0950ef2196	cc0dc39f-c6fd-4e0d-81bb-e9ea0bcd1ed6
\.


--
-- Data for Name: component; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.component (id, name, parent_id, provider_id, provider_type, realm_id, sub_type) FROM stdin;
b2cc1cc1-cae9-4202-bf6c-e975e50d96e8	Trusted Hosts	5be18a3e-7181-4862-867b-45aff91b9b87	trusted-hosts	org.keycloak.services.clientregistration.policy.ClientRegistrationPolicy	5be18a3e-7181-4862-867b-45aff91b9b87	anonymous
6333ad9d-a647-4307-aae9-19c9994c6a24	Consent Required	5be18a3e-7181-4862-867b-45aff91b9b87	consent-required	org.keycloak.services.clientregistration.policy.ClientRegistrationPolicy	5be18a3e-7181-4862-867b-45aff91b9b87	anonymous
f4654453-bba6-4d09-be60-bffb3943bed2	Full Scope Disabled	5be18a3e-7181-4862-867b-45aff91b9b87	scope	org.keycloak.services.clientregistration.policy.ClientRegistrationPolicy	5be18a3e-7181-4862-867b-45aff91b9b87	anonymous
4e086da0-2504-42ac-b19a-c5c863fb4877	Max Clients Limit	5be18a3e-7181-4862-867b-45aff91b9b87	max-clients	org.keycloak.services.clientregistration.policy.ClientRegistrationPolicy	5be18a3e-7181-4862-867b-45aff91b9b87	anonymous
48e52a80-17fe-4202-b8cc-8c8da1b76499	Allowed Protocol Mapper Types	5be18a3e-7181-4862-867b-45aff91b9b87	allowed-protocol-mappers	org.keycloak.services.clientregistration.policy.ClientRegistrationPolicy	5be18a3e-7181-4862-867b-45aff91b9b87	anonymous
9bd45864-a625-4082-93ce-348d82a326d7	Allowed Client Scopes	5be18a3e-7181-4862-867b-45aff91b9b87	allowed-client-templates	org.keycloak.services.clientregistration.policy.ClientRegistrationPolicy	5be18a3e-7181-4862-867b-45aff91b9b87	anonymous
f95fbfa6-fa86-4069-9779-9f80015e22d7	Allowed Protocol Mapper Types	5be18a3e-7181-4862-867b-45aff91b9b87	allowed-protocol-mappers	org.keycloak.services.clientregistration.policy.ClientRegistrationPolicy	5be18a3e-7181-4862-867b-45aff91b9b87	authenticated
c7fa580f-95e1-4a18-a7d6-079b8b110b96	Allowed Client Scopes	5be18a3e-7181-4862-867b-45aff91b9b87	allowed-client-templates	org.keycloak.services.clientregistration.policy.ClientRegistrationPolicy	5be18a3e-7181-4862-867b-45aff91b9b87	authenticated
b42e60ef-cd88-45f7-bece-c87418c5f718	rsa-generated	5be18a3e-7181-4862-867b-45aff91b9b87	rsa-generated	org.keycloak.keys.KeyProvider	5be18a3e-7181-4862-867b-45aff91b9b87	\N
5894a8b0-e2c5-48ba-8127-73badbf7edd7	rsa-enc-generated	5be18a3e-7181-4862-867b-45aff91b9b87	rsa-enc-generated	org.keycloak.keys.KeyProvider	5be18a3e-7181-4862-867b-45aff91b9b87	\N
ecb8ae1b-6f83-4a5b-bd32-96f78d79c895	hmac-generated-hs512	5be18a3e-7181-4862-867b-45aff91b9b87	hmac-generated	org.keycloak.keys.KeyProvider	5be18a3e-7181-4862-867b-45aff91b9b87	\N
c7e6fa64-211f-49b4-a8e0-b410e35ea622	aes-generated	5be18a3e-7181-4862-867b-45aff91b9b87	aes-generated	org.keycloak.keys.KeyProvider	5be18a3e-7181-4862-867b-45aff91b9b87	\N
f1ebd68f-7b1c-4ecd-a9a5-1ceb779b6e68	\N	5be18a3e-7181-4862-867b-45aff91b9b87	declarative-user-profile	org.keycloak.userprofile.UserProfileProvider	5be18a3e-7181-4862-867b-45aff91b9b87	\N
e671da6f-e34d-417c-9b67-cb260855d3d1	rsa-generated	21dfe33f-5923-4bfd-bc04-cf200e747656	rsa-generated	org.keycloak.keys.KeyProvider	21dfe33f-5923-4bfd-bc04-cf200e747656	\N
7bfa786c-77a0-4a9c-899f-3015c88b16c7	rsa-enc-generated	21dfe33f-5923-4bfd-bc04-cf200e747656	rsa-enc-generated	org.keycloak.keys.KeyProvider	21dfe33f-5923-4bfd-bc04-cf200e747656	\N
79592aa2-4961-4673-b5a5-9b2835de2603	hmac-generated-hs512	21dfe33f-5923-4bfd-bc04-cf200e747656	hmac-generated	org.keycloak.keys.KeyProvider	21dfe33f-5923-4bfd-bc04-cf200e747656	\N
f4a173c7-a308-4f51-9d61-cd062fd607b8	aes-generated	21dfe33f-5923-4bfd-bc04-cf200e747656	aes-generated	org.keycloak.keys.KeyProvider	21dfe33f-5923-4bfd-bc04-cf200e747656	\N
41032afa-64a9-4770-a451-5677fcba5973	Trusted Hosts	21dfe33f-5923-4bfd-bc04-cf200e747656	trusted-hosts	org.keycloak.services.clientregistration.policy.ClientRegistrationPolicy	21dfe33f-5923-4bfd-bc04-cf200e747656	anonymous
3d47f4a5-1a17-4921-9df7-8723582b9a75	Consent Required	21dfe33f-5923-4bfd-bc04-cf200e747656	consent-required	org.keycloak.services.clientregistration.policy.ClientRegistrationPolicy	21dfe33f-5923-4bfd-bc04-cf200e747656	anonymous
e0b8bd27-8c92-43ef-ab60-aea08310d829	Full Scope Disabled	21dfe33f-5923-4bfd-bc04-cf200e747656	scope	org.keycloak.services.clientregistration.policy.ClientRegistrationPolicy	21dfe33f-5923-4bfd-bc04-cf200e747656	anonymous
33013985-ffeb-42f0-b949-68d805cf871b	Max Clients Limit	21dfe33f-5923-4bfd-bc04-cf200e747656	max-clients	org.keycloak.services.clientregistration.policy.ClientRegistrationPolicy	21dfe33f-5923-4bfd-bc04-cf200e747656	anonymous
7d872658-d920-4885-acaa-647d62983af9	Allowed Protocol Mapper Types	21dfe33f-5923-4bfd-bc04-cf200e747656	allowed-protocol-mappers	org.keycloak.services.clientregistration.policy.ClientRegistrationPolicy	21dfe33f-5923-4bfd-bc04-cf200e747656	anonymous
5bcd47e7-0c15-46b3-b7cf-a19507a7b74e	Allowed Client Scopes	21dfe33f-5923-4bfd-bc04-cf200e747656	allowed-client-templates	org.keycloak.services.clientregistration.policy.ClientRegistrationPolicy	21dfe33f-5923-4bfd-bc04-cf200e747656	anonymous
47248290-0186-4576-8a4e-a1c95b255dfd	Allowed Protocol Mapper Types	21dfe33f-5923-4bfd-bc04-cf200e747656	allowed-protocol-mappers	org.keycloak.services.clientregistration.policy.ClientRegistrationPolicy	21dfe33f-5923-4bfd-bc04-cf200e747656	authenticated
5fac5de1-b750-48ca-b4a6-eefc0f48a3e2	Allowed Client Scopes	21dfe33f-5923-4bfd-bc04-cf200e747656	allowed-client-templates	org.keycloak.services.clientregistration.policy.ClientRegistrationPolicy	21dfe33f-5923-4bfd-bc04-cf200e747656	authenticated
\.


--
-- Data for Name: component_config; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.component_config (id, component_id, name, value) FROM stdin;
fb7b166a-fd66-45cc-9956-d69b99319632	48e52a80-17fe-4202-b8cc-8c8da1b76499	allowed-protocol-mapper-types	oidc-full-name-mapper
5fdc5a21-698b-437d-8fbc-fb7fcde0a86a	48e52a80-17fe-4202-b8cc-8c8da1b76499	allowed-protocol-mapper-types	saml-role-list-mapper
ab6f5027-5670-4d56-93d0-e4384bf591c5	48e52a80-17fe-4202-b8cc-8c8da1b76499	allowed-protocol-mapper-types	saml-user-attribute-mapper
c459de97-bf95-44c3-8cec-3046ec26ab7f	48e52a80-17fe-4202-b8cc-8c8da1b76499	allowed-protocol-mapper-types	oidc-usermodel-attribute-mapper
c31054d5-b459-46dd-a3aa-a2dac75ae641	48e52a80-17fe-4202-b8cc-8c8da1b76499	allowed-protocol-mapper-types	saml-user-property-mapper
f0cc3c4d-43f6-49b9-9f42-6f993cef6c4b	48e52a80-17fe-4202-b8cc-8c8da1b76499	allowed-protocol-mapper-types	oidc-usermodel-property-mapper
094de31b-986e-4559-a02e-ad15b7460b97	48e52a80-17fe-4202-b8cc-8c8da1b76499	allowed-protocol-mapper-types	oidc-address-mapper
a251a0e2-11ae-4941-b71f-09f93b385372	48e52a80-17fe-4202-b8cc-8c8da1b76499	allowed-protocol-mapper-types	oidc-sha256-pairwise-sub-mapper
0efe8552-944d-4eac-b2f6-e2ec4225a902	b2cc1cc1-cae9-4202-bf6c-e975e50d96e8	host-sending-registration-request-must-match	true
eff9dbca-bf9b-4d46-8f82-124e91ec8af1	b2cc1cc1-cae9-4202-bf6c-e975e50d96e8	client-uris-must-match	true
8bab3eb3-8d81-44b4-bcb9-947f816b94aa	4e086da0-2504-42ac-b19a-c5c863fb4877	max-clients	200
f79d894e-8f31-4a2a-a521-dc0a96a049e8	f95fbfa6-fa86-4069-9779-9f80015e22d7	allowed-protocol-mapper-types	saml-user-attribute-mapper
4689579b-7c87-4f4f-9a00-b2f4763b6db5	f95fbfa6-fa86-4069-9779-9f80015e22d7	allowed-protocol-mapper-types	oidc-full-name-mapper
60b4a84d-ba01-4dab-bb64-3a5a207d1a70	f95fbfa6-fa86-4069-9779-9f80015e22d7	allowed-protocol-mapper-types	oidc-address-mapper
a3095860-f64a-4e70-863a-99590bc7fd0c	f95fbfa6-fa86-4069-9779-9f80015e22d7	allowed-protocol-mapper-types	oidc-sha256-pairwise-sub-mapper
8aa892d5-5be1-48a3-bd01-0fce25549e38	f95fbfa6-fa86-4069-9779-9f80015e22d7	allowed-protocol-mapper-types	oidc-usermodel-property-mapper
f9d3a7cc-5043-44a4-ac09-f9377123a0e0	f95fbfa6-fa86-4069-9779-9f80015e22d7	allowed-protocol-mapper-types	saml-role-list-mapper
260f0a3e-3fd5-4c22-8f8b-bca527dea822	f95fbfa6-fa86-4069-9779-9f80015e22d7	allowed-protocol-mapper-types	saml-user-property-mapper
c68f20df-93b0-4abc-892c-d896a5fd3c1d	f95fbfa6-fa86-4069-9779-9f80015e22d7	allowed-protocol-mapper-types	oidc-usermodel-attribute-mapper
39c5fe33-d537-42c0-aab2-2d3a349f545c	9bd45864-a625-4082-93ce-348d82a326d7	allow-default-scopes	true
ccd6b68c-87fe-4094-90eb-0c61a607ab1b	c7fa580f-95e1-4a18-a7d6-079b8b110b96	allow-default-scopes	true
1e66bc6f-f84b-4d34-9f51-551115a39638	c7e6fa64-211f-49b4-a8e0-b410e35ea622	kid	a3f7b0c3-7797-48ce-9414-b034121c52b2
8160ce56-a1e3-409c-bdf9-9af6ede463a2	c7e6fa64-211f-49b4-a8e0-b410e35ea622	secret	fP91Oct76B6TKLyBcF4ccg
ab73a5a3-c462-44a5-9fef-1d95df9ecd60	c7e6fa64-211f-49b4-a8e0-b410e35ea622	priority	100
2b125c32-4a6b-434e-a997-60abd8cf6d9f	f1ebd68f-7b1c-4ecd-a9a5-1ceb779b6e68	kc.user.profile.config	{"attributes":[{"name":"username","displayName":"${username}","validations":{"length":{"min":3,"max":255},"username-prohibited-characters":{},"up-username-not-idn-homograph":{}},"permissions":{"view":["admin","user"],"edit":["admin","user"]},"multivalued":false},{"name":"email","displayName":"${email}","validations":{"email":{},"length":{"max":255}},"permissions":{"view":["admin","user"],"edit":["admin","user"]},"multivalued":false},{"name":"firstName","displayName":"${firstName}","validations":{"length":{"max":255},"person-name-prohibited-characters":{}},"permissions":{"view":["admin","user"],"edit":["admin","user"]},"multivalued":false},{"name":"lastName","displayName":"${lastName}","validations":{"length":{"max":255},"person-name-prohibited-characters":{}},"permissions":{"view":["admin","user"],"edit":["admin","user"]},"multivalued":false}],"groups":[{"name":"user-metadata","displayHeader":"User metadata","displayDescription":"Attributes, which refer to user metadata"}]}
38f4734e-99c8-43b9-9919-9e08c8a5e243	b42e60ef-cd88-45f7-bece-c87418c5f718	certificate	MIICmzCCAYMCBgGaX/kttTANBgkqhkiG9w0BAQsFADARMQ8wDQYDVQQDDAZtYXN0ZXIwHhcNMjUxMTA3MjAxNzM3WhcNMzUxMTA3MjAxOTE3WjARMQ8wDQYDVQQDDAZtYXN0ZXIwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQClA/B1hQDCl7pwpW8WovX4LY7/GVTIRehSx8Nq6g4ZZk9acaOtZhIL4ojcrXDbIN9VLK4f2tu22X9GhkL8L6XjBCHufhBIxwT1YxxpkxaFhrhLwmQUhpW+iovKXDKDW2NUpMVKYN0L+o6HTfEyioISaFjfBtBCboqZEVYyQeLGtp34BBXQ6RcsiHtddI1LeSpRDRDbqrk67iUfu42+NwCH94YO/hafqp139iqbIg4FIeFOm14HQ8lUqlO8Ssfp5LcGdMpEJe9nY0mWLUh25Leg06Q0m8U3NObQ9gY3Q29jp9Q57aBUmVhVG96T9tZRVaFuLIps9ZJfe462uEZ6F3dVAgMBAAEwDQYJKoZIhvcNAQELBQADggEBAFKg54MyblI54S8ZJ6jDl0JjfU83yxpFtjUhwxU5KIHn0vIWdwRKix++Mu4Ug/4W0kOvmWRvkKwc+tWO2GTQCZm/vCnf0h4uNcsic4Ul3pyjXzMmI+ch6wIOinffFPx5DwMZhQAbLXBtkLPyePoBVwVQQJVTFU+G7AjEKkW45xfUqB/FsXq+sFdNULdCK3sRX0qP/80VyJUXPcCYI2h4gfr4j6tboYf8ZEy720Cpf5zTomctqx6N3R8IC8qt4zPZm+GvB4QvIFz5kCijOS6ae0KgOPNSVf/RjPsFEF549FjCcS3oGVm9wXUX1A3se76CGMXWmwUffA+bWCo4VHO2qxQ=
57a0f334-e1cb-479b-8eba-edec561e69ae	b42e60ef-cd88-45f7-bece-c87418c5f718	privateKey	MIIEowIBAAKCAQEApQPwdYUAwpe6cKVvFqL1+C2O/xlUyEXoUsfDauoOGWZPWnGjrWYSC+KI3K1w2yDfVSyuH9rbttl/RoZC/C+l4wQh7n4QSMcE9WMcaZMWhYa4S8JkFIaVvoqLylwyg1tjVKTFSmDdC/qOh03xMoqCEmhY3wbQQm6KmRFWMkHixrad+AQV0OkXLIh7XXSNS3kqUQ0Q26q5Ou4lH7uNvjcAh/eGDv4Wn6qdd/YqmyIOBSHhTpteB0PJVKpTvErH6eS3BnTKRCXvZ2NJli1IduS3oNOkNJvFNzTm0PYGN0NvY6fUOe2gVJlYVRvek/bWUVWhbiyKbPWSX3uOtrhGehd3VQIDAQABAoIBABT0oxzJfzHhwt4l+YLjvwjSqvjfu/yS+XtJvcSzZIb6jyk/3+FYDQKlX2wRj+YZY+3qdqe6S3IKZ4y1Otx70JKRJnNQXxEJn9Tpzo85tqp4/qk1o9qsx2d4gLgkwpAb6Elfg2PRWUD5g2V7aHNaqO9dgQERrxuV836Xd7LPhdUQ4lQU9k6ib9nnXNia8AT2EKefLH3V+5W8L3CCmzAMHXUtvVYaVGdwZrQ2QhlwMqUs9vc7hNYoRhjzZMHDiL6ge1kxzessSUcry/cKDNhlLU8ACTHTSonKUXJycLM8I4E+xlZjBBjH8jnXcP24EXNXZDIYdSUC+rV5gy6RecQctyECgYEA1CeyvJLI1HJ2AlkCDuNj17NXgjbzS+NJDLADH9UqCWNZEqkarzgvVrjetDCBoKD8O1Hs7l1fA/bySItR966RmDM8ZoZtKLVgWYtga2wsd84gTxk57QVgkgHboHkmrmMzDtVzTlbolFwBVusdXkBUYjxBgJN2/Pq5ge9pqmkOtHsCgYEAxx5DabN7G+Cl6PuDXyh9plpKOVjubBRkN/Qgu8CiPuAHnInTVPnpkzdFCdMjS619Saluft5lgFhsZ7iM35YBsNwqov5KJs3obd0CY2fWgVCGyXFz1nrYqTrtrdUDM2zSs9gsZvRhG9lPBVPByhGNmxlp31tBEsu7y7rxLEI2wm8CgYB1AFu7Ubw+Jc3dJ5dR/KfAeqClKIbu8C8GNz/R225udQLXnrkfrv20dwojF6k1m/LfCCSBpK7U8ejWhzcyQGz9IiyKYlJrI/Q6Dfqj46l2fRAmb0QZ6mBCxZGJI6dofz7WTHNl3dowj7kRZWLx6speztpU/X6er+uEtDNzDrNUZwKBgQDE41zfUPTjbPBA/yo41s3fxxnruM8Qmd07Iq+XV3RW3alJFVOdi/x1cEpY26jj9OmVA+9Zjckp7sVKjkbl8us7GYkjYHSsCCDTOZ1Z89w8RAbze7aCFzjTpYxNvfqLSAjUgmXta6n2IpurddWCXHb8LVXt4MrorgHFAtXk4JhLCwKBgFf3OSjIXZs9XxL94XS1Nc6FBVLSNsAYfZcw0Plrudj1tmlEFmxtuedojVxORQMnC1XYKq0B9rMQGphm+z2CSsHerf4WHRhwLdeCAMDgRbZKN8NCFNgOEeaYRl7olY0+AmLljI7FMt3cD8KzimwLPt7ccK3sMuo3nGI0k+Wz7lT+
de8f5c1a-3918-4acd-adf4-cf777c5b76cd	b42e60ef-cd88-45f7-bece-c87418c5f718	keyUse	SIG
2f5b4e8c-3ad6-4821-8326-eb82069dc0f9	b42e60ef-cd88-45f7-bece-c87418c5f718	priority	100
cba9d0d5-e51c-4fbf-9d64-c92aae9bcd96	ecb8ae1b-6f83-4a5b-bd32-96f78d79c895	secret	swyJcs7kvVHYhDBe85eUzsgUXUJ3De-d8W8BRTEs5sws8JoRADZfnUnWo3a50eO2Ty1T-_boLKzGfFpWCTezl_FloWfXRUyiIXL5AytTlCsIxKrwFAl7_YQ3yzXdk-C6-Z5V6d6SRwGxIh8bvZY6qJYLcpVmJtndaGFb8gUdrWo
6edd0418-c71b-420b-b3db-91f5346807b9	ecb8ae1b-6f83-4a5b-bd32-96f78d79c895	algorithm	HS512
8ae425a0-118d-4462-b21e-0a821d729112	ecb8ae1b-6f83-4a5b-bd32-96f78d79c895	priority	100
0a38feda-8961-4873-86e3-2689cc561e4a	ecb8ae1b-6f83-4a5b-bd32-96f78d79c895	kid	9d936394-6d0d-4169-b15c-0f2f98b9c61b
0c0cde45-75bb-488f-a661-36fc5bebe592	5894a8b0-e2c5-48ba-8127-73badbf7edd7	priority	100
64e36af0-9cc6-48f7-bab6-4e607d992d05	5894a8b0-e2c5-48ba-8127-73badbf7edd7	privateKey	MIIEowIBAAKCAQEAsCfsUH/Q1753p3uT60/MfIUmeTnYrrM2YCkgW9TpaTejmPTjFVji6nv5W24gSEo/vYCd7J/wUszJU7dkq3BxphLcrsn5rZ8UuKD6c8/881qrBE+xeArTPa1F6BLAhyTwfax4NuJG/WvJV5Zq9Om0cRgtF2UyfY5cSwulhp0jI1JpKX4n7k97ROqASJI1gbTtjFcgWiFn2r7Vp+RhwzzpBrfwdVh7mnDf/I/6Sc0jymlo6nL8ssLeR0xZux33gSr8+r9y0deSCI5cqcdjp4SX0va9nlRewfFZxw47BKAXWn/S+S3Nkh2AiGwHee8kEiW3WFOkitOlBmzIDjCD7qaA3QIDAQABAoH/bAgP5U59xdIJj606ChXmUndWIQJY4MsHjfGq5qasftqgei21FmJsx2FAi9H9+leOv6khMPzlZeIxliXil0FecXsf3BICDXiCPLh84Imtl5EDUKGPNQ9ufWTGeo0FhdwhoPEkyIP9BW4VDKIy9gBdqP4qqS5myJmGAIAkA2pbIk1jlI7GUvA7mkceWijWaKNzvz/uMorLr9xRcN+KF976rrS5391wHLIqR9UBLQzPmqhXQc2vBm0JD3RRWmtFwUelwVr//6f0pcaDuwFh4nTRC1ljnKXd4fcNc5aO2KZK3MCMPHG8rIgFbLl7IDEieROs/t24ylBvi+ORQ3XmRVntAoGBANt11EsELSXKh7gs0xXSIt5779W3RhQwp/uZgIj7B42GUbbZYdzEbix3//FmbLUPseHVqqf9c6praKp0rSVchX6Sx1njnbhdnzuVdp7KU2UdJdAc/TcSt9mx7UjUdEmFPVGKzR1Ut2UaVq4NXRKH1ctUrTMAAMtPANmtfvE7xrx7AoGBAM18T5pBBbTMtmU/Km6oRaYUJpgsr1AHl6iluKsuQ+oW7OWA6REDcsI7MP8Xd0go1Pe63Z/+gabWMvdVi4U48Xl1Akejx8jd65qMIUxhiBsQ26KP9IpIxdXS3HJLjWmIjNfe5nB0ZpqvuI96JgasNZcbOafpVo7v9lgdy2V7BpSHAoGBAMioWa0lampNXf6F7ZLcCcnHJCkSY97+BfnEBoQ4klVSZNB8vj/u0pWSOtBryCVc7lYA2QK0eNdvUcnY2J96kwyCBAgqWAFEiN0f8c+KSun+1p4Mg3GhibxgNQcMSi8WxlQSRyz0UqL8jBikW18gF9jL2XjyHcfGuo5NVe4Xq8SVAoGBAJ/jJEVQZtJBn4K0XZ3wzRDnCQjLbDYHUlhlaoW34BxbbkU9wxv75OWBDSTP6354Vw3TlvMRI2zfqpSNOZyVrD7nbrizlZaUJukANECsey0kNuIMxSh8a4NvKRy98PC20XB+/ituRxABvsfVMZVrld9Xzcr7YuChkrsJo+P4kCwtAoGBAM+jstCaoo4EnS5VrtMICgwNyHYr9sr97Jn4qrcOzmcTVOMpnyY2zE3C2NaHqzrzqkrnKlHXmjP2pD0slTlLhmqeZlHA3zltFJgk3xTtDuEahfuBPDcpEn+PBCB0bRkg/kUoFWHqSF/rpPpnLas4qhauRHV2KkChHf/3dMRTdcP+
d03965ed-1aaa-4cbf-9d64-96b809455477	5894a8b0-e2c5-48ba-8127-73badbf7edd7	certificate	MIICmzCCAYMCBgGaX/kumjANBgkqhkiG9w0BAQsFADARMQ8wDQYDVQQDDAZtYXN0ZXIwHhcNMjUxMTA3MjAxNzM3WhcNMzUxMTA3MjAxOTE3WjARMQ8wDQYDVQQDDAZtYXN0ZXIwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCwJ+xQf9DXvnene5PrT8x8hSZ5OdiuszZgKSBb1OlpN6OY9OMVWOLqe/lbbiBISj+9gJ3sn/BSzMlTt2SrcHGmEtyuyfmtnxS4oPpzz/zzWqsET7F4CtM9rUXoEsCHJPB9rHg24kb9a8lXlmr06bRxGC0XZTJ9jlxLC6WGnSMjUmkpfifuT3tE6oBIkjWBtO2MVyBaIWfavtWn5GHDPOkGt/B1WHuacN/8j/pJzSPKaWjqcvyywt5HTFm7HfeBKvz6v3LR15IIjlypx2OnhJfS9r2eVF7B8VnHDjsEoBdaf9L5Lc2SHYCIbAd57yQSJbdYU6SK06UGbMgOMIPupoDdAgMBAAEwDQYJKoZIhvcNAQELBQADggEBAFzgvfoUlAkalvC3hBKi2nHKLav3lidB0ROU+3+2ChFqW2auCHoiHsgWezVGq+YEWnSKQgmTpeB3+XmAmvET5R+8gWdBR/8B7HJvf2xdWbEmUnXoTCNTX+ghUIP+T5RhNlv7gXVk3mGd2c1PCais78Rnlt/nsTQMzxDnOBFsOG7yucTeqGvWkgsad182V5826oE/6J09kVqIQpEFqnjDE9xWt4r1SA3MLeQBI3xzJQGgCepps3hhlmfDwGL/Y5x4bDoQY6d9hT1NkubdR8/o+NHSci0QtszMKTkd+ckxPBMdmV6g1wi6wBeIeM7Bhq8vWF3zw5jSd9rnE12ROdCpdaI=
1a024c56-4b25-49f6-b156-534f0fe84ead	5894a8b0-e2c5-48ba-8127-73badbf7edd7	keyUse	ENC
fccd920b-4a47-4ffd-9a92-5469a69c2c2f	5894a8b0-e2c5-48ba-8127-73badbf7edd7	algorithm	RSA-OAEP
5e4be253-37e3-4da7-9427-548906ac8798	e671da6f-e34d-417c-9b67-cb260855d3d1	privateKey	MIIEpAIBAAKCAQEA0J9XTs2JkbWojo9sk8vbGJoidrk7ZIBPfm8TxxKfp4IX29m732a/tsQcIwOeglaQO04WJSG9FywogKaAxBG0QwkJdp1BVJX5HwbPZF70KTzsCMhsckb4CDwQnyMpFMcSs7iyPmfc9CY/eLvNyuIX+Tm/J8sf34tsJxQfn3FG/EpRGBjVEEsEXVZG7NsuJsoV0Meq+WYmKoHAK2luOWgXucyCFYYzE5Bl+oglQobhc0K1aJTA39Ur9xw/eLXdKj7OVJat0ra7NfcbDXSyN4ho1DqtCzX5x1QSs9biCSoCI1o8oH7jOKd+2h1zeTNNM7Wul7wzR/F4ilQc/v/NpqzsoQIDAQABAoIBAAWA6xzP7fruO1AnuScm3tDFze6Cr2YUzxgOYEvJXlUtCMHo2wibL2gAAV+keIS+6a0ZV7rm+nv1Sxwd/F4Tyx0EvLtUfaMAhfj1OSDYUw3QksfeaPM8s13U/xGiK+r9j5UWfHwKSZdGqChwUKb7TwNo/D2lmYGgThATuyv1uSgWFfz9RzfHFw1uLnR3vIHZpZLU63bObrM2ACdk5SMqVUPNgiZgIGimJEsABYIkElS8YlKVmV6tEqPZQimwyOHUdOOYbcF+Nf+41GBND24Um4NZ2WEuXDuk0ZfdEWRluOAvfpuV4hyVz++zBqkIq4LQfrnDhbX8fqN2gfZpCHcFYoECgYEA7+D+fVTNuHWULk5280I4HejSHJ9ksSmBjNXWZJt0g99+Uv+pNCionuxKNy4bA8dEaSNwGnXr1NrPG9l0btoac4JLet4JijrhxKaTpmrxv/h8uUIsqpyN665HQAN17qhxKPZMVScS6VVJpfMf4QI1V3gNGXhU6HaGHQajt7wFWCECgYEA3qSYDmbFSd3Gapvyosw6EBTvxRhNBLCRnKRRRpXYKGcisMs4+ZCUW5FeBxRi6WvKnNf3doOJQrA+T9eyXGS4TOBqScGeyb1EJBlFlFrXeQ03y0Y3s07ze4BX2eMTNA4vjnyZBK/jZpCeUIxJnnmQgtccek9dsDqT16RxACM7BIECgYEAtdt4dGIXeJHDXnvkGDYKvzokGMkKmHlkGvZ/DFUCt3t3lMr4Z2+vrpRrC3xrxKiMh7zzH0xpFz0vqOhqKiQ1y35rZOHyj5ZmVSUIaTFIyAZF4Fl37Xy054l/wNsezGltKOXZJvFxl+4t4J76eyamdAKyw62DiZ1ZvaWr9v6XeqECgYACdacIYbJEQqLygo6HpeHuU4zijIYtSxYQuO/866Lbr2f+tAAJIcPBzzVOtrbxBTPTz774HDPj/LZzg1qBEsvGbaQ+9FigueqKy4ytOuOufqrjH/91h6XA84YE7jFEHfQAivfVyWulsmtNUH9vtMAX8fBqmX3beIoxk6t76Oe6AQKBgQCJsxVwmVtVEEernorb6daSXxg5gk2yH9uqmmF1bDHorGL4ZtbirdMtWcbF2FBaFQRDFGoHA/uRSDfHZny/ztHu5kI2/pI4B6dUymayeSv/9Ec+MdO23DYkJgWUJ8JpqCND/QhAuxoblw6VWpgZi/VG1El9pepImFo+L8Uhg9ohlA==
678ecf94-0051-4250-b339-d8589d80a541	e671da6f-e34d-417c-9b67-cb260855d3d1	certificate	MIICmTCCAYECBgGaX/tRezANBgkqhkiG9w0BAQsFADAQMQ4wDAYDVQQDDAVsb2NhbDAeFw0yNTExMDcyMDE5NTdaFw0zNTExMDcyMDIxMzdaMBAxDjAMBgNVBAMMBWxvY2FsMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA0J9XTs2JkbWojo9sk8vbGJoidrk7ZIBPfm8TxxKfp4IX29m732a/tsQcIwOeglaQO04WJSG9FywogKaAxBG0QwkJdp1BVJX5HwbPZF70KTzsCMhsckb4CDwQnyMpFMcSs7iyPmfc9CY/eLvNyuIX+Tm/J8sf34tsJxQfn3FG/EpRGBjVEEsEXVZG7NsuJsoV0Meq+WYmKoHAK2luOWgXucyCFYYzE5Bl+oglQobhc0K1aJTA39Ur9xw/eLXdKj7OVJat0ra7NfcbDXSyN4ho1DqtCzX5x1QSs9biCSoCI1o8oH7jOKd+2h1zeTNNM7Wul7wzR/F4ilQc/v/NpqzsoQIDAQABMA0GCSqGSIb3DQEBCwUAA4IBAQA7y/U9UIMsq8mCu9kQn9JuUaXTi0vimNeEvnViU81Ee7gRC/eZ4Wey1rpyC6zBBwndwLAgGg7F486cIjj1oaIdNNwkvixUoHnc0iniL2NT2611PKwo+Heu0K8X+lSmfdGEHujG1Aslc/I3Hpj4dT8OkGYKd/tW9tApNi2pLM4P7bR7HCTGayzzXxLPUVkPOkcgk/FP7ulZgdVUETubagyyFrdC/cIcla15B4mm9VqHY+bRh6lKBboaGwXujUXk9MlDKmdTAg9KLxbiINZVW/Im/1NP7Xmu6pspYP3kku/aJVJr9l/S5h8/fSK50xW6BFtG4JH8+xpuwYgqO/7KgHzE
10f93737-b2f6-4c87-8652-4ab9e9fe2094	e671da6f-e34d-417c-9b67-cb260855d3d1	keyUse	SIG
930cbc28-7b31-4893-887b-d21b88ed8f74	e671da6f-e34d-417c-9b67-cb260855d3d1	priority	100
2608cb82-7578-47d8-a95a-9e0793104a0b	f4a173c7-a308-4f51-9d61-cd062fd607b8	priority	100
a7e9dc21-b294-412c-9de1-6e8b17b7bf00	f4a173c7-a308-4f51-9d61-cd062fd607b8	secret	EDjkv1Dx5eFaaicWOre5ng
7b4be573-a6f9-44e2-8a4b-21044fd63597	f4a173c7-a308-4f51-9d61-cd062fd607b8	kid	47cf1de3-947c-404d-8826-7e044a0bab50
a48ecedd-51b6-4dc9-a4a2-9ba717341acc	79592aa2-4961-4673-b5a5-9b2835de2603	algorithm	HS512
bf6df9c8-6d6f-4df3-995d-0f892c61fa7e	79592aa2-4961-4673-b5a5-9b2835de2603	secret	cs6l1y1uvFKkgKTOfde5Pb80QNU3L9hPyCKvi28fMdy0NevY2jurvg5jHytnmiQtovb3yu0a8r_pu-JfCb1ukZ_mPc_d7dex1BY_GP9nADF4mo4ZnT2n983gGNHIXaIAm1GVj1THC_40VQV6ueJGLdOCG_HfBML0e_6R_aLevi0
eec2f8ad-407a-4b6a-8aca-d21d90deabfe	79592aa2-4961-4673-b5a5-9b2835de2603	priority	100
fb46644d-ef32-4b5f-8a1e-ca8a9c9ddd21	79592aa2-4961-4673-b5a5-9b2835de2603	kid	8324a79f-3932-4aa4-abfe-8263d93b5271
8fd67f56-94d2-4057-b71a-8e45d553dc84	7bfa786c-77a0-4a9c-899f-3015c88b16c7	privateKey	MIIEpAIBAAKCAQEA3woRNHtV9gjaWvMUW34RRF2G8dGRP+s47u/R8oQmKETlRPij3fer3NFnefG/pP62DSdHhpzHE9UyJNfKCpk4LSahXL8qEuuxFoMXZTTEbUpog3BPLvuhCorbZIOBOn0VLmscAyqxlxffbPnLeDmHyOhZYiAWQsSpx2HguSSm49VM4LvxetGupFBcA+sdW/DQn3M/oKerbons8QKdf2X9rrsmQScZblINfxhwROLWYWaaTDxMDt1rEM8bitmcZnvdjKjGJksAAQ4b54sBeRsxr9/FBJSxCe4lD6+fC92xQlbLoQXu4noS1CiRHmMw/OJ4ba3U/+pJ0xfpnNgKyP7rsQIDAQABAoIBABNXcOcDdBCmM2NUNZV6kP5D+w4Q3Z70o8cKqoL0pUd0NAqfYjx/PBrl2OqZBYTGJtzspVX91gC5CgRqZyW0pEu8EB22ISyrXjvEyfxXj1on6/jL/j3lidFbecuVYNlE3Beep7r5kpV290PgxJ2MJaONTKUHAc8v9UYqTX3YuRVEMlVEWXrsXBPNP4FpdtCrJ3UBgAGfdDSX0aYWEwwgny3e8tXeKezmcFDud1rFWvf0zhTZ4uAkXJjVz17UmBUsrdIc4fr8PCBK2FOgCmwO+Ira9bIUXxcAt7t/YZwiCMOiyEipHbBrf5hZLuqHNrXzU72+zpZX6+b2MYgdvgOKEK0CgYEA9YrljzZTDJ1e4DLn01u7zn8key2MKRqqGZdolS0dQ6Z/BR9rxgmWVBMsqtV9padogCznUIRERmExdNUo3284ltjVsZiKabFPN1LQ20FnlIzlHC7XBaGmOzRdFkxhVUs2F2ueSarNlj9d9YxCNMXvtpGL/vvEgU8sMTZ50p7J8tUCgYEA6InSbmrVugo3hoel0ow1DDWAzNhNUy+w7FfBjZxXVHIPwEtGMktHJnggamDB8A/qCG9yAO8pNTVhTfzrOKV48nSvbzwK+S7rshk4f1V+AZJOkGtAmHAdt/XH8C5eMfnflZHOpZCg5fKSt8ghrDJaHWYLovOJd57Rw31LcPE1620CgYEA4aMB0Nja+Hyk8uHUpyVlMB0mKQtyAVO/fETmli8e9UvK7aoyH4ov2pLEOTh2fgOYxDB/YD4rf4FRMUuwg6JxHi2kMc87YmTNpskzpEg2JwxSfdONRF+HomA8KoGF8BttWZhLnOaYhbk1Xq/FJzm9TsfxHh++NBXNRmwJBsNkUQECgYB0lx2d5Qzx8UtztTFsBoZWb8D7c/wZGFFRvpI6CUgz+9hv5o30i4/J9vLxwz+ZuLDzt8TmOQNlPTVjX8skJLsmfWC0mds6os7kBgcwuNGrwgqIGG5Tv+r2oFG119m8nvb+TBPbKU+y21O6t6pCZyCNmut8sTSceFHd/UVFBHuvZQKBgQDsHowBQH02HY4v3Z/6YcqzOHKuRwnqf6JrplRzKCzGOF1V6xO3ZA39U60U1idr8Lt7/8l4vG1SQbtmUkzyvDMQ94xXkoEXbst65qgorFnfjez0Zzk8Z/OtAyUrfl+g+g44U79zJnt6yOf5CnqhCwcReOKMiRFzlVGrq66jOkrKxA==
fc4a1a15-8a89-4dac-86be-e3f4a0a767c5	7bfa786c-77a0-4a9c-899f-3015c88b16c7	priority	100
f468438d-6ce3-4c72-a9bd-b11fdb3d595b	7bfa786c-77a0-4a9c-899f-3015c88b16c7	keyUse	ENC
9c26eb03-b0b8-4fcc-b370-ee550e96723a	7bfa786c-77a0-4a9c-899f-3015c88b16c7	algorithm	RSA-OAEP
29b5be4b-1065-4782-8894-ae2d5ce9d297	7bfa786c-77a0-4a9c-899f-3015c88b16c7	certificate	MIICmTCCAYECBgGaX/tR5zANBgkqhkiG9w0BAQsFADAQMQ4wDAYDVQQDDAVsb2NhbDAeFw0yNTExMDcyMDE5NTdaFw0zNTExMDcyMDIxMzdaMBAxDjAMBgNVBAMMBWxvY2FsMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA3woRNHtV9gjaWvMUW34RRF2G8dGRP+s47u/R8oQmKETlRPij3fer3NFnefG/pP62DSdHhpzHE9UyJNfKCpk4LSahXL8qEuuxFoMXZTTEbUpog3BPLvuhCorbZIOBOn0VLmscAyqxlxffbPnLeDmHyOhZYiAWQsSpx2HguSSm49VM4LvxetGupFBcA+sdW/DQn3M/oKerbons8QKdf2X9rrsmQScZblINfxhwROLWYWaaTDxMDt1rEM8bitmcZnvdjKjGJksAAQ4b54sBeRsxr9/FBJSxCe4lD6+fC92xQlbLoQXu4noS1CiRHmMw/OJ4ba3U/+pJ0xfpnNgKyP7rsQIDAQABMA0GCSqGSIb3DQEBCwUAA4IBAQA1/Qlr2hCZQOwbjPJbpCU25zsxjSNEx5wnmZTPp/M+QkUSJ89jTywy4wwDNyKhAD/eSajEhfZavGPQimuLty/yRXlW6SzPcO9AZwdpEmhS7VRzTkltCdKi7Br5LEU1YwVV81hM9Dgjoy4tGmu8cAcdkx3g1rdN20hegtBmkBLQ2srMUkrNtPt+TkmO8Qi/QNFg+ztyyRhdP22nstyLzBXsVbjzme4XzmJh0wsgS5FrWF/OnoMCQnm38daZB70E7QwxcmT3PbeEhdybcmsS2H/QHX53cl33SFGRizPptL1+ANbC56u8IpjLsxASmuaCLMIi/FTXY9X/TGxl5jRRH0hf
a8d7af2f-9508-449a-abb8-653f3f2118b9	47248290-0186-4576-8a4e-a1c95b255dfd	allowed-protocol-mapper-types	saml-user-attribute-mapper
f05aa60a-7dee-40a6-8685-c5cfcb00a39a	47248290-0186-4576-8a4e-a1c95b255dfd	allowed-protocol-mapper-types	oidc-usermodel-property-mapper
af7f3d0e-8f0f-4497-a8c5-7d2cf1e2fd98	47248290-0186-4576-8a4e-a1c95b255dfd	allowed-protocol-mapper-types	saml-role-list-mapper
0d1bdd89-1928-4569-9ede-a0cb9761addb	47248290-0186-4576-8a4e-a1c95b255dfd	allowed-protocol-mapper-types	oidc-usermodel-attribute-mapper
414adc2e-37ae-4cc5-bbad-59d219c0d9b6	47248290-0186-4576-8a4e-a1c95b255dfd	allowed-protocol-mapper-types	oidc-address-mapper
bc0db1af-e66d-4801-a1f6-d0f3afd9e5d3	47248290-0186-4576-8a4e-a1c95b255dfd	allowed-protocol-mapper-types	oidc-full-name-mapper
7c102ba0-3d00-4d3a-88a5-0fe3f6165f37	47248290-0186-4576-8a4e-a1c95b255dfd	allowed-protocol-mapper-types	saml-user-property-mapper
1fc18d1f-88e8-4d24-962b-08630bb48037	47248290-0186-4576-8a4e-a1c95b255dfd	allowed-protocol-mapper-types	oidc-sha256-pairwise-sub-mapper
2e9b1ee1-4ade-4465-a13b-25da318cb9b0	5fac5de1-b750-48ca-b4a6-eefc0f48a3e2	allow-default-scopes	true
f21df117-61b0-4d7a-b832-f2fcaa40dab7	33013985-ffeb-42f0-b949-68d805cf871b	max-clients	200
8ed25b33-3057-4fb3-b899-761ecf6141db	7d872658-d920-4885-acaa-647d62983af9	allowed-protocol-mapper-types	oidc-usermodel-attribute-mapper
6360dc9a-2c3f-4a12-84ec-d6fa1da3b1b6	7d872658-d920-4885-acaa-647d62983af9	allowed-protocol-mapper-types	oidc-address-mapper
71e0fff9-da7c-4e37-af73-f01eedb83836	7d872658-d920-4885-acaa-647d62983af9	allowed-protocol-mapper-types	saml-role-list-mapper
586a27ef-4a6c-4196-a8b5-47c60dae8d02	7d872658-d920-4885-acaa-647d62983af9	allowed-protocol-mapper-types	oidc-full-name-mapper
217aebfe-5967-462b-b1c3-f90de6350cac	7d872658-d920-4885-acaa-647d62983af9	allowed-protocol-mapper-types	oidc-sha256-pairwise-sub-mapper
b0977e07-6d01-4a06-b534-46be4ddf66a5	7d872658-d920-4885-acaa-647d62983af9	allowed-protocol-mapper-types	saml-user-property-mapper
98ff0846-ee5c-4f91-9915-f26b4e205d6b	7d872658-d920-4885-acaa-647d62983af9	allowed-protocol-mapper-types	oidc-usermodel-property-mapper
d33c5b76-9c2b-48fd-88cd-eb64280dcccc	7d872658-d920-4885-acaa-647d62983af9	allowed-protocol-mapper-types	saml-user-attribute-mapper
1671252b-9cdd-4fae-8fc2-50888c820e57	41032afa-64a9-4770-a451-5677fcba5973	host-sending-registration-request-must-match	true
83476d2e-2ea7-4e57-a611-d26c99ffbe93	41032afa-64a9-4770-a451-5677fcba5973	client-uris-must-match	true
fd83af96-7c49-47f2-8110-8dc019396e0c	5bcd47e7-0c15-46b3-b7cf-a19507a7b74e	allow-default-scopes	true
\.


--
-- Data for Name: composite_role; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.composite_role (composite, child_role) FROM stdin;
e7ecdf7c-50e6-4c10-b17f-8075d29c107c	4bd7b272-2bff-4959-ad20-f9438630c2a2
e7ecdf7c-50e6-4c10-b17f-8075d29c107c	52f5dcd2-5b12-49e4-bae9-b99e0b630422
e7ecdf7c-50e6-4c10-b17f-8075d29c107c	5457fffa-b9fd-4b86-bcf1-f4a3009eb7c8
e7ecdf7c-50e6-4c10-b17f-8075d29c107c	34954d6e-4e14-4c18-ae2c-08f9d2455f0d
e7ecdf7c-50e6-4c10-b17f-8075d29c107c	c74a110d-d528-464c-8957-37070c1d0cae
e7ecdf7c-50e6-4c10-b17f-8075d29c107c	7d7d85d6-1d1b-4210-b520-7b2cad173cd4
e7ecdf7c-50e6-4c10-b17f-8075d29c107c	730f195b-7671-4a4f-8e6b-02da8d7d0931
e7ecdf7c-50e6-4c10-b17f-8075d29c107c	66dba1f0-0546-4212-99f8-6748abcd92e0
e7ecdf7c-50e6-4c10-b17f-8075d29c107c	d706ce26-1d31-4ec5-9613-9853bb7aeaae
e7ecdf7c-50e6-4c10-b17f-8075d29c107c	92ee1845-7384-4a41-abb8-957cf6dedb5b
e7ecdf7c-50e6-4c10-b17f-8075d29c107c	d8fcc45c-ac4f-4dfc-b0d7-87b5fcfab5e6
e7ecdf7c-50e6-4c10-b17f-8075d29c107c	f9e6b7fd-ca54-41b3-af13-c25c6edbcf3f
e7ecdf7c-50e6-4c10-b17f-8075d29c107c	d2276970-2146-43da-972a-11a1a8e9e2a9
e7ecdf7c-50e6-4c10-b17f-8075d29c107c	d8eb9aa1-8b4a-4c1e-9b8f-73d3b07780b4
e7ecdf7c-50e6-4c10-b17f-8075d29c107c	d33628b0-7a53-4be2-9c1b-c3723cfc6f2b
e7ecdf7c-50e6-4c10-b17f-8075d29c107c	656b2728-ed10-4826-9a50-31a4e259cd87
e7ecdf7c-50e6-4c10-b17f-8075d29c107c	ca02fd4e-9a60-4bf5-809e-c1a0431a0d23
e7ecdf7c-50e6-4c10-b17f-8075d29c107c	e180f3e9-0bc3-482f-9e53-8ba7ac88a09a
34954d6e-4e14-4c18-ae2c-08f9d2455f0d	e180f3e9-0bc3-482f-9e53-8ba7ac88a09a
34954d6e-4e14-4c18-ae2c-08f9d2455f0d	d33628b0-7a53-4be2-9c1b-c3723cfc6f2b
88007421-49af-4531-9b09-3025a88deb0f	77df31c7-b5c4-4835-ae49-cfe0ed6a8f1e
c74a110d-d528-464c-8957-37070c1d0cae	656b2728-ed10-4826-9a50-31a4e259cd87
88007421-49af-4531-9b09-3025a88deb0f	79d032d2-4b1f-4b01-9418-fa6ad7e29efd
79d032d2-4b1f-4b01-9418-fa6ad7e29efd	38cfe765-0c0a-457e-a516-f72985e8169b
0e67c975-30bf-44be-9a8f-f62403b9baee	34778562-adf1-404c-98e5-dcb5cc9da021
e7ecdf7c-50e6-4c10-b17f-8075d29c107c	b9040c2a-3367-4272-968d-d6c5f4ed6623
88007421-49af-4531-9b09-3025a88deb0f	e23e71ce-b6c5-4aa7-9077-bf1cb8878745
88007421-49af-4531-9b09-3025a88deb0f	2a4954f4-f206-4ce4-b19f-b744d2d5ea44
e7ecdf7c-50e6-4c10-b17f-8075d29c107c	e3537e6b-8379-467f-bfe8-15cdc4a32f52
e7ecdf7c-50e6-4c10-b17f-8075d29c107c	f1007e04-3356-41b5-9d6f-7043f7c2c701
e7ecdf7c-50e6-4c10-b17f-8075d29c107c	022693bc-6df4-4889-895e-e904c52bd3a2
e7ecdf7c-50e6-4c10-b17f-8075d29c107c	6cf31d65-54a3-432e-874e-cd9fc49c6642
e7ecdf7c-50e6-4c10-b17f-8075d29c107c	44258421-f818-4834-b96e-2eb0fc51f36d
e7ecdf7c-50e6-4c10-b17f-8075d29c107c	3901f48f-bd83-433e-affc-45db7f50e220
e7ecdf7c-50e6-4c10-b17f-8075d29c107c	b02d5067-0e48-438b-9b57-14f323515384
e7ecdf7c-50e6-4c10-b17f-8075d29c107c	86c01e31-5dd9-484c-ace5-8b7690f7e416
e7ecdf7c-50e6-4c10-b17f-8075d29c107c	322035e2-a62a-4931-a600-d0170fbf6df7
e7ecdf7c-50e6-4c10-b17f-8075d29c107c	a1f76f7e-31e1-4c60-bebc-31ad66d25983
e7ecdf7c-50e6-4c10-b17f-8075d29c107c	5923bcb5-4829-43a5-9171-0a59eb980095
e7ecdf7c-50e6-4c10-b17f-8075d29c107c	c94843e6-4cfd-4a4d-890c-d6343a90ffb7
e7ecdf7c-50e6-4c10-b17f-8075d29c107c	fc9d6a3e-64b2-4b6d-946e-3ca669750b05
e7ecdf7c-50e6-4c10-b17f-8075d29c107c	dbba3239-df15-4dc7-804c-638b80862e85
e7ecdf7c-50e6-4c10-b17f-8075d29c107c	859cd9c7-3246-47db-94c8-7dbb36bd4361
e7ecdf7c-50e6-4c10-b17f-8075d29c107c	c5c23393-73b2-4a00-a8da-e1ceed33fcc8
e7ecdf7c-50e6-4c10-b17f-8075d29c107c	dae29efa-69ba-4e6c-8793-cadfd2824e3f
022693bc-6df4-4889-895e-e904c52bd3a2	dae29efa-69ba-4e6c-8793-cadfd2824e3f
022693bc-6df4-4889-895e-e904c52bd3a2	dbba3239-df15-4dc7-804c-638b80862e85
6cf31d65-54a3-432e-874e-cd9fc49c6642	859cd9c7-3246-47db-94c8-7dbb36bd4361
00d3f0d7-d0a6-46a6-a328-577f85af26b4	150e4aa0-1449-4dca-a879-ba26b20dadfe
00d3f0d7-d0a6-46a6-a328-577f85af26b4	cc386f4e-f506-403e-b285-95cd0fa0d867
00d3f0d7-d0a6-46a6-a328-577f85af26b4	7b858e3a-ae86-427a-a84a-8f9deaf6501d
00d3f0d7-d0a6-46a6-a328-577f85af26b4	e542a3c9-c10c-4abc-a38b-079bd23afee2
00d3f0d7-d0a6-46a6-a328-577f85af26b4	ede5fd63-28d0-479c-924b-1e32391f8648
00d3f0d7-d0a6-46a6-a328-577f85af26b4	638475f1-e7f1-45ee-8dff-20606259e993
00d3f0d7-d0a6-46a6-a328-577f85af26b4	b5e10000-5cc3-4f0c-9894-e13bc0b61bf7
00d3f0d7-d0a6-46a6-a328-577f85af26b4	461d3a94-99f9-425b-89d8-9fa2bec03ab7
00d3f0d7-d0a6-46a6-a328-577f85af26b4	7db617b0-8dff-40d9-a47b-cc7b092fe9e5
00d3f0d7-d0a6-46a6-a328-577f85af26b4	de27b490-ec70-4c3e-9c6c-c45d6e7d73a4
00d3f0d7-d0a6-46a6-a328-577f85af26b4	6ee08807-aa8d-402c-a0cc-d6c7f920d930
00d3f0d7-d0a6-46a6-a328-577f85af26b4	539a1ff1-d18c-4d67-ac93-fbe774d11be9
00d3f0d7-d0a6-46a6-a328-577f85af26b4	1f25af04-e298-46ae-9570-273328c82de8
00d3f0d7-d0a6-46a6-a328-577f85af26b4	62c510c3-abf2-418b-8a12-f8ea21199f05
00d3f0d7-d0a6-46a6-a328-577f85af26b4	99f49fc8-c08e-4c20-b20f-c3626592aad6
00d3f0d7-d0a6-46a6-a328-577f85af26b4	6095ffc1-62ed-4169-b614-7d0b166a99db
00d3f0d7-d0a6-46a6-a328-577f85af26b4	8acb6c84-2b3c-470c-a003-0a6f0f2b48f1
0a8a743d-b0e0-4d1e-8747-7513a1e564d1	9164548b-a33a-434d-ab72-fabd8d248706
7b858e3a-ae86-427a-a84a-8f9deaf6501d	8acb6c84-2b3c-470c-a003-0a6f0f2b48f1
7b858e3a-ae86-427a-a84a-8f9deaf6501d	62c510c3-abf2-418b-8a12-f8ea21199f05
e542a3c9-c10c-4abc-a38b-079bd23afee2	99f49fc8-c08e-4c20-b20f-c3626592aad6
0a8a743d-b0e0-4d1e-8747-7513a1e564d1	c2a86f85-7cc1-4205-b98a-42b8557945e1
c2a86f85-7cc1-4205-b98a-42b8557945e1	26bb3b89-c68d-4c8e-aeaa-a98f91087c9f
ef743bff-0eee-40ef-ab63-8eac0cc21101	40c60837-b911-4bc0-aea5-26a9852c207c
e7ecdf7c-50e6-4c10-b17f-8075d29c107c	4f9f1fd9-8af5-48d5-b275-5974bcddd8f6
00d3f0d7-d0a6-46a6-a328-577f85af26b4	42e83457-164e-4ee2-a679-58886b5f3357
0a8a743d-b0e0-4d1e-8747-7513a1e564d1	cc0dc39f-c6fd-4e0d-81bb-e9ea0bcd1ed6
0a8a743d-b0e0-4d1e-8747-7513a1e564d1	5f7c14f8-1f1f-4742-9640-6834529d865d
\.


--
-- Data for Name: credential; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.credential (id, salt, type, user_id, created_date, user_label, secret_data, credential_data, priority) FROM stdin;
457d5a13-31a3-46e2-a5f6-7fee74b94faa	\N	password	c3557eb9-249e-4dd9-b72d-9d2977b1af9d	1762546757552	\N	{"value":"Fs+O7KDqMtopv4LxDq7vPNH5SOMzyyFlG4I2koMScB8=","salt":"d396/AFHTh/rJVApbHVaSg==","additionalParameters":{}}	{"hashIterations":5,"algorithm":"argon2","additionalParameters":{"hashLength":["32"],"memory":["7168"],"type":["id"],"version":["1.3"],"parallelism":["1"]}}	10
fb0f5faf-b2c6-4037-bb68-6012f710eb30	\N	password	dde646db-f964-4728-9ce9-e9552001b16a	1762546966086	My password	{"value":"FzWQg+91Puj3zYtLMlvKz27Jvy08bJWn51Cg/ooPMu8=","salt":"gW691SCojVcpc5PELlDP1g==","additionalParameters":{}}	{"hashIterations":5,"algorithm":"argon2","additionalParameters":{"hashLength":["32"],"memory":["7168"],"type":["id"],"version":["1.3"],"parallelism":["1"]}}	10
\.


--
-- Data for Name: databasechangelog; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.databasechangelog (id, author, filename, dateexecuted, orderexecuted, exectype, md5sum, description, comments, tag, liquibase, contexts, labels, deployment_id) FROM stdin;
1.0.0.Final-KEYCLOAK-5461	sthorger@redhat.com	META-INF/jpa-changelog-1.0.0.Final.xml	2025-11-07 20:19:02.810396	1	EXECUTED	9:6f1016664e21e16d26517a4418f5e3df	createTable tableName=APPLICATION_DEFAULT_ROLES; createTable tableName=CLIENT; createTable tableName=CLIENT_SESSION; createTable tableName=CLIENT_SESSION_ROLE; createTable tableName=COMPOSITE_ROLE; createTable tableName=CREDENTIAL; createTable tab...		\N	4.29.1	\N	\N	2546741820
1.0.0.Final-KEYCLOAK-5461	sthorger@redhat.com	META-INF/db2-jpa-changelog-1.0.0.Final.xml	2025-11-07 20:19:02.83889	2	MARK_RAN	9:828775b1596a07d1200ba1d49e5e3941	createTable tableName=APPLICATION_DEFAULT_ROLES; createTable tableName=CLIENT; createTable tableName=CLIENT_SESSION; createTable tableName=CLIENT_SESSION_ROLE; createTable tableName=COMPOSITE_ROLE; createTable tableName=CREDENTIAL; createTable tab...		\N	4.29.1	\N	\N	2546741820
1.1.0.Beta1	sthorger@redhat.com	META-INF/jpa-changelog-1.1.0.Beta1.xml	2025-11-07 20:19:02.941412	3	EXECUTED	9:5f090e44a7d595883c1fb61f4b41fd38	delete tableName=CLIENT_SESSION_ROLE; delete tableName=CLIENT_SESSION; delete tableName=USER_SESSION; createTable tableName=CLIENT_ATTRIBUTES; createTable tableName=CLIENT_SESSION_NOTE; createTable tableName=APP_NODE_REGISTRATIONS; addColumn table...		\N	4.29.1	\N	\N	2546741820
1.1.0.Final	sthorger@redhat.com	META-INF/jpa-changelog-1.1.0.Final.xml	2025-11-07 20:19:02.957665	4	EXECUTED	9:c07e577387a3d2c04d1adc9aaad8730e	renameColumn newColumnName=EVENT_TIME, oldColumnName=TIME, tableName=EVENT_ENTITY		\N	4.29.1	\N	\N	2546741820
1.2.0.Beta1	psilva@redhat.com	META-INF/jpa-changelog-1.2.0.Beta1.xml	2025-11-07 20:19:03.191719	5	EXECUTED	9:b68ce996c655922dbcd2fe6b6ae72686	delete tableName=CLIENT_SESSION_ROLE; delete tableName=CLIENT_SESSION_NOTE; delete tableName=CLIENT_SESSION; delete tableName=USER_SESSION; createTable tableName=PROTOCOL_MAPPER; createTable tableName=PROTOCOL_MAPPER_CONFIG; createTable tableName=...		\N	4.29.1	\N	\N	2546741820
1.2.0.Beta1	psilva@redhat.com	META-INF/db2-jpa-changelog-1.2.0.Beta1.xml	2025-11-07 20:19:03.207028	6	MARK_RAN	9:543b5c9989f024fe35c6f6c5a97de88e	delete tableName=CLIENT_SESSION_ROLE; delete tableName=CLIENT_SESSION_NOTE; delete tableName=CLIENT_SESSION; delete tableName=USER_SESSION; createTable tableName=PROTOCOL_MAPPER; createTable tableName=PROTOCOL_MAPPER_CONFIG; createTable tableName=...		\N	4.29.1	\N	\N	2546741820
1.2.0.RC1	bburke@redhat.com	META-INF/jpa-changelog-1.2.0.CR1.xml	2025-11-07 20:19:03.441128	7	EXECUTED	9:765afebbe21cf5bbca048e632df38336	delete tableName=CLIENT_SESSION_ROLE; delete tableName=CLIENT_SESSION_NOTE; delete tableName=CLIENT_SESSION; delete tableName=USER_SESSION_NOTE; delete tableName=USER_SESSION; createTable tableName=MIGRATION_MODEL; createTable tableName=IDENTITY_P...		\N	4.29.1	\N	\N	2546741820
1.2.0.RC1	bburke@redhat.com	META-INF/db2-jpa-changelog-1.2.0.CR1.xml	2025-11-07 20:19:03.451541	8	MARK_RAN	9:db4a145ba11a6fdaefb397f6dbf829a1	delete tableName=CLIENT_SESSION_ROLE; delete tableName=CLIENT_SESSION_NOTE; delete tableName=CLIENT_SESSION; delete tableName=USER_SESSION_NOTE; delete tableName=USER_SESSION; createTable tableName=MIGRATION_MODEL; createTable tableName=IDENTITY_P...		\N	4.29.1	\N	\N	2546741820
1.2.0.Final	keycloak	META-INF/jpa-changelog-1.2.0.Final.xml	2025-11-07 20:19:03.476109	9	EXECUTED	9:9d05c7be10cdb873f8bcb41bc3a8ab23	update tableName=CLIENT; update tableName=CLIENT; update tableName=CLIENT		\N	4.29.1	\N	\N	2546741820
1.3.0	bburke@redhat.com	META-INF/jpa-changelog-1.3.0.xml	2025-11-07 20:19:03.721237	10	EXECUTED	9:18593702353128d53111f9b1ff0b82b8	delete tableName=CLIENT_SESSION_ROLE; delete tableName=CLIENT_SESSION_PROT_MAPPER; delete tableName=CLIENT_SESSION_NOTE; delete tableName=CLIENT_SESSION; delete tableName=USER_SESSION_NOTE; delete tableName=USER_SESSION; createTable tableName=ADMI...		\N	4.29.1	\N	\N	2546741820
1.4.0	bburke@redhat.com	META-INF/jpa-changelog-1.4.0.xml	2025-11-07 20:19:03.865726	11	EXECUTED	9:6122efe5f090e41a85c0f1c9e52cbb62	delete tableName=CLIENT_SESSION_AUTH_STATUS; delete tableName=CLIENT_SESSION_ROLE; delete tableName=CLIENT_SESSION_PROT_MAPPER; delete tableName=CLIENT_SESSION_NOTE; delete tableName=CLIENT_SESSION; delete tableName=USER_SESSION_NOTE; delete table...		\N	4.29.1	\N	\N	2546741820
1.4.0	bburke@redhat.com	META-INF/db2-jpa-changelog-1.4.0.xml	2025-11-07 20:19:03.874674	12	MARK_RAN	9:e1ff28bf7568451453f844c5d54bb0b5	delete tableName=CLIENT_SESSION_AUTH_STATUS; delete tableName=CLIENT_SESSION_ROLE; delete tableName=CLIENT_SESSION_PROT_MAPPER; delete tableName=CLIENT_SESSION_NOTE; delete tableName=CLIENT_SESSION; delete tableName=USER_SESSION_NOTE; delete table...		\N	4.29.1	\N	\N	2546741820
1.5.0	bburke@redhat.com	META-INF/jpa-changelog-1.5.0.xml	2025-11-07 20:19:03.954682	13	EXECUTED	9:7af32cd8957fbc069f796b61217483fd	delete tableName=CLIENT_SESSION_AUTH_STATUS; delete tableName=CLIENT_SESSION_ROLE; delete tableName=CLIENT_SESSION_PROT_MAPPER; delete tableName=CLIENT_SESSION_NOTE; delete tableName=CLIENT_SESSION; delete tableName=USER_SESSION_NOTE; delete table...		\N	4.29.1	\N	\N	2546741820
1.6.1_from15	mposolda@redhat.com	META-INF/jpa-changelog-1.6.1.xml	2025-11-07 20:19:03.995409	14	EXECUTED	9:6005e15e84714cd83226bf7879f54190	addColumn tableName=REALM; addColumn tableName=KEYCLOAK_ROLE; addColumn tableName=CLIENT; createTable tableName=OFFLINE_USER_SESSION; createTable tableName=OFFLINE_CLIENT_SESSION; addPrimaryKey constraintName=CONSTRAINT_OFFL_US_SES_PK2, tableName=...		\N	4.29.1	\N	\N	2546741820
1.6.1_from16-pre	mposolda@redhat.com	META-INF/jpa-changelog-1.6.1.xml	2025-11-07 20:19:04.001253	15	MARK_RAN	9:bf656f5a2b055d07f314431cae76f06c	delete tableName=OFFLINE_CLIENT_SESSION; delete tableName=OFFLINE_USER_SESSION		\N	4.29.1	\N	\N	2546741820
1.6.1_from16	mposolda@redhat.com	META-INF/jpa-changelog-1.6.1.xml	2025-11-07 20:19:04.009278	16	MARK_RAN	9:f8dadc9284440469dcf71e25ca6ab99b	dropPrimaryKey constraintName=CONSTRAINT_OFFLINE_US_SES_PK, tableName=OFFLINE_USER_SESSION; dropPrimaryKey constraintName=CONSTRAINT_OFFLINE_CL_SES_PK, tableName=OFFLINE_CLIENT_SESSION; addColumn tableName=OFFLINE_USER_SESSION; update tableName=OF...		\N	4.29.1	\N	\N	2546741820
1.6.1	mposolda@redhat.com	META-INF/jpa-changelog-1.6.1.xml	2025-11-07 20:19:04.022658	17	EXECUTED	9:d41d8cd98f00b204e9800998ecf8427e	empty		\N	4.29.1	\N	\N	2546741820
1.7.0	bburke@redhat.com	META-INF/jpa-changelog-1.7.0.xml	2025-11-07 20:19:04.120569	18	EXECUTED	9:3368ff0be4c2855ee2dd9ca813b38d8e	createTable tableName=KEYCLOAK_GROUP; createTable tableName=GROUP_ROLE_MAPPING; createTable tableName=GROUP_ATTRIBUTE; createTable tableName=USER_GROUP_MEMBERSHIP; createTable tableName=REALM_DEFAULT_GROUPS; addColumn tableName=IDENTITY_PROVIDER; ...		\N	4.29.1	\N	\N	2546741820
1.8.0	mposolda@redhat.com	META-INF/jpa-changelog-1.8.0.xml	2025-11-07 20:19:04.21817	19	EXECUTED	9:8ac2fb5dd030b24c0570a763ed75ed20	addColumn tableName=IDENTITY_PROVIDER; createTable tableName=CLIENT_TEMPLATE; createTable tableName=CLIENT_TEMPLATE_ATTRIBUTES; createTable tableName=TEMPLATE_SCOPE_MAPPING; dropNotNullConstraint columnName=CLIENT_ID, tableName=PROTOCOL_MAPPER; ad...		\N	4.29.1	\N	\N	2546741820
1.8.0-2	keycloak	META-INF/jpa-changelog-1.8.0.xml	2025-11-07 20:19:04.237369	20	EXECUTED	9:f91ddca9b19743db60e3057679810e6c	dropDefaultValue columnName=ALGORITHM, tableName=CREDENTIAL; update tableName=CREDENTIAL		\N	4.29.1	\N	\N	2546741820
1.8.0	mposolda@redhat.com	META-INF/db2-jpa-changelog-1.8.0.xml	2025-11-07 20:19:04.245436	21	MARK_RAN	9:831e82914316dc8a57dc09d755f23c51	addColumn tableName=IDENTITY_PROVIDER; createTable tableName=CLIENT_TEMPLATE; createTable tableName=CLIENT_TEMPLATE_ATTRIBUTES; createTable tableName=TEMPLATE_SCOPE_MAPPING; dropNotNullConstraint columnName=CLIENT_ID, tableName=PROTOCOL_MAPPER; ad...		\N	4.29.1	\N	\N	2546741820
1.8.0-2	keycloak	META-INF/db2-jpa-changelog-1.8.0.xml	2025-11-07 20:19:04.254234	22	MARK_RAN	9:f91ddca9b19743db60e3057679810e6c	dropDefaultValue columnName=ALGORITHM, tableName=CREDENTIAL; update tableName=CREDENTIAL		\N	4.29.1	\N	\N	2546741820
1.9.0	mposolda@redhat.com	META-INF/jpa-changelog-1.9.0.xml	2025-11-07 20:19:04.416018	23	EXECUTED	9:bc3d0f9e823a69dc21e23e94c7a94bb1	update tableName=REALM; update tableName=REALM; update tableName=REALM; update tableName=REALM; update tableName=CREDENTIAL; update tableName=CREDENTIAL; update tableName=CREDENTIAL; update tableName=REALM; update tableName=REALM; customChange; dr...		\N	4.29.1	\N	\N	2546741820
1.9.1	keycloak	META-INF/jpa-changelog-1.9.1.xml	2025-11-07 20:19:04.436194	24	EXECUTED	9:c9999da42f543575ab790e76439a2679	modifyDataType columnName=PRIVATE_KEY, tableName=REALM; modifyDataType columnName=PUBLIC_KEY, tableName=REALM; modifyDataType columnName=CERTIFICATE, tableName=REALM		\N	4.29.1	\N	\N	2546741820
1.9.1	keycloak	META-INF/db2-jpa-changelog-1.9.1.xml	2025-11-07 20:19:04.442703	25	MARK_RAN	9:0d6c65c6f58732d81569e77b10ba301d	modifyDataType columnName=PRIVATE_KEY, tableName=REALM; modifyDataType columnName=CERTIFICATE, tableName=REALM		\N	4.29.1	\N	\N	2546741820
1.9.2	keycloak	META-INF/jpa-changelog-1.9.2.xml	2025-11-07 20:19:05.225899	26	EXECUTED	9:fc576660fc016ae53d2d4778d84d86d0	createIndex indexName=IDX_USER_EMAIL, tableName=USER_ENTITY; createIndex indexName=IDX_USER_ROLE_MAPPING, tableName=USER_ROLE_MAPPING; createIndex indexName=IDX_USER_GROUP_MAPPING, tableName=USER_GROUP_MEMBERSHIP; createIndex indexName=IDX_USER_CO...		\N	4.29.1	\N	\N	2546741820
authz-2.0.0	psilva@redhat.com	META-INF/jpa-changelog-authz-2.0.0.xml	2025-11-07 20:19:05.337778	27	EXECUTED	9:43ed6b0da89ff77206289e87eaa9c024	createTable tableName=RESOURCE_SERVER; addPrimaryKey constraintName=CONSTRAINT_FARS, tableName=RESOURCE_SERVER; addUniqueConstraint constraintName=UK_AU8TT6T700S9V50BU18WS5HA6, tableName=RESOURCE_SERVER; createTable tableName=RESOURCE_SERVER_RESOU...		\N	4.29.1	\N	\N	2546741820
authz-2.5.1	psilva@redhat.com	META-INF/jpa-changelog-authz-2.5.1.xml	2025-11-07 20:19:05.351502	28	EXECUTED	9:44bae577f551b3738740281eceb4ea70	update tableName=RESOURCE_SERVER_POLICY		\N	4.29.1	\N	\N	2546741820
2.1.0-KEYCLOAK-5461	bburke@redhat.com	META-INF/jpa-changelog-2.1.0.xml	2025-11-07 20:19:05.433835	29	EXECUTED	9:bd88e1f833df0420b01e114533aee5e8	createTable tableName=BROKER_LINK; createTable tableName=FED_USER_ATTRIBUTE; createTable tableName=FED_USER_CONSENT; createTable tableName=FED_USER_CONSENT_ROLE; createTable tableName=FED_USER_CONSENT_PROT_MAPPER; createTable tableName=FED_USER_CR...		\N	4.29.1	\N	\N	2546741820
2.2.0	bburke@redhat.com	META-INF/jpa-changelog-2.2.0.xml	2025-11-07 20:19:05.465141	30	EXECUTED	9:a7022af5267f019d020edfe316ef4371	addColumn tableName=ADMIN_EVENT_ENTITY; createTable tableName=CREDENTIAL_ATTRIBUTE; createTable tableName=FED_CREDENTIAL_ATTRIBUTE; modifyDataType columnName=VALUE, tableName=CREDENTIAL; addForeignKeyConstraint baseTableName=FED_CREDENTIAL_ATTRIBU...		\N	4.29.1	\N	\N	2546741820
2.3.0	bburke@redhat.com	META-INF/jpa-changelog-2.3.0.xml	2025-11-07 20:19:05.522921	31	EXECUTED	9:fc155c394040654d6a79227e56f5e25a	createTable tableName=FEDERATED_USER; addPrimaryKey constraintName=CONSTR_FEDERATED_USER, tableName=FEDERATED_USER; dropDefaultValue columnName=TOTP, tableName=USER_ENTITY; dropColumn columnName=TOTP, tableName=USER_ENTITY; addColumn tableName=IDE...		\N	4.29.1	\N	\N	2546741820
2.4.0	bburke@redhat.com	META-INF/jpa-changelog-2.4.0.xml	2025-11-07 20:19:05.539187	32	EXECUTED	9:eac4ffb2a14795e5dc7b426063e54d88	customChange		\N	4.29.1	\N	\N	2546741820
2.5.0	bburke@redhat.com	META-INF/jpa-changelog-2.5.0.xml	2025-11-07 20:19:05.561045	33	EXECUTED	9:54937c05672568c4c64fc9524c1e9462	customChange; modifyDataType columnName=USER_ID, tableName=OFFLINE_USER_SESSION		\N	4.29.1	\N	\N	2546741820
2.5.0-unicode-oracle	hmlnarik@redhat.com	META-INF/jpa-changelog-2.5.0.xml	2025-11-07 20:19:05.56809	34	MARK_RAN	9:3a32bace77c84d7678d035a7f5a8084e	modifyDataType columnName=DESCRIPTION, tableName=AUTHENTICATION_FLOW; modifyDataType columnName=DESCRIPTION, tableName=CLIENT_TEMPLATE; modifyDataType columnName=DESCRIPTION, tableName=RESOURCE_SERVER_POLICY; modifyDataType columnName=DESCRIPTION,...		\N	4.29.1	\N	\N	2546741820
2.5.0-unicode-other-dbs	hmlnarik@redhat.com	META-INF/jpa-changelog-2.5.0.xml	2025-11-07 20:19:05.64241	35	EXECUTED	9:33d72168746f81f98ae3a1e8e0ca3554	modifyDataType columnName=DESCRIPTION, tableName=AUTHENTICATION_FLOW; modifyDataType columnName=DESCRIPTION, tableName=CLIENT_TEMPLATE; modifyDataType columnName=DESCRIPTION, tableName=RESOURCE_SERVER_POLICY; modifyDataType columnName=DESCRIPTION,...		\N	4.29.1	\N	\N	2546741820
2.5.0-duplicate-email-support	slawomir@dabek.name	META-INF/jpa-changelog-2.5.0.xml	2025-11-07 20:19:05.659844	36	EXECUTED	9:61b6d3d7a4c0e0024b0c839da283da0c	addColumn tableName=REALM		\N	4.29.1	\N	\N	2546741820
2.5.0-unique-group-names	hmlnarik@redhat.com	META-INF/jpa-changelog-2.5.0.xml	2025-11-07 20:19:05.674262	37	EXECUTED	9:8dcac7bdf7378e7d823cdfddebf72fda	addUniqueConstraint constraintName=SIBLING_NAMES, tableName=KEYCLOAK_GROUP		\N	4.29.1	\N	\N	2546741820
2.5.1	bburke@redhat.com	META-INF/jpa-changelog-2.5.1.xml	2025-11-07 20:19:05.688744	38	EXECUTED	9:a2b870802540cb3faa72098db5388af3	addColumn tableName=FED_USER_CONSENT		\N	4.29.1	\N	\N	2546741820
3.0.0	bburke@redhat.com	META-INF/jpa-changelog-3.0.0.xml	2025-11-07 20:19:05.702593	39	EXECUTED	9:132a67499ba24bcc54fb5cbdcfe7e4c0	addColumn tableName=IDENTITY_PROVIDER		\N	4.29.1	\N	\N	2546741820
3.2.0-fix	keycloak	META-INF/jpa-changelog-3.2.0.xml	2025-11-07 20:19:05.70897	40	MARK_RAN	9:938f894c032f5430f2b0fafb1a243462	addNotNullConstraint columnName=REALM_ID, tableName=CLIENT_INITIAL_ACCESS		\N	4.29.1	\N	\N	2546741820
3.2.0-fix-with-keycloak-5416	keycloak	META-INF/jpa-changelog-3.2.0.xml	2025-11-07 20:19:05.718045	41	MARK_RAN	9:845c332ff1874dc5d35974b0babf3006	dropIndex indexName=IDX_CLIENT_INIT_ACC_REALM, tableName=CLIENT_INITIAL_ACCESS; addNotNullConstraint columnName=REALM_ID, tableName=CLIENT_INITIAL_ACCESS; createIndex indexName=IDX_CLIENT_INIT_ACC_REALM, tableName=CLIENT_INITIAL_ACCESS		\N	4.29.1	\N	\N	2546741820
3.2.0-fix-offline-sessions	hmlnarik	META-INF/jpa-changelog-3.2.0.xml	2025-11-07 20:19:05.739499	42	EXECUTED	9:fc86359c079781adc577c5a217e4d04c	customChange		\N	4.29.1	\N	\N	2546741820
3.2.0-fixed	keycloak	META-INF/jpa-changelog-3.2.0.xml	2025-11-07 20:19:08.534665	43	EXECUTED	9:59a64800e3c0d09b825f8a3b444fa8f4	addColumn tableName=REALM; dropPrimaryKey constraintName=CONSTRAINT_OFFL_CL_SES_PK2, tableName=OFFLINE_CLIENT_SESSION; dropColumn columnName=CLIENT_SESSION_ID, tableName=OFFLINE_CLIENT_SESSION; addPrimaryKey constraintName=CONSTRAINT_OFFL_CL_SES_P...		\N	4.29.1	\N	\N	2546741820
3.3.0	keycloak	META-INF/jpa-changelog-3.3.0.xml	2025-11-07 20:19:08.550633	44	EXECUTED	9:d48d6da5c6ccf667807f633fe489ce88	addColumn tableName=USER_ENTITY		\N	4.29.1	\N	\N	2546741820
authz-3.4.0.CR1-resource-server-pk-change-part1	glavoie@gmail.com	META-INF/jpa-changelog-authz-3.4.0.CR1.xml	2025-11-07 20:19:08.57014	45	EXECUTED	9:dde36f7973e80d71fceee683bc5d2951	addColumn tableName=RESOURCE_SERVER_POLICY; addColumn tableName=RESOURCE_SERVER_RESOURCE; addColumn tableName=RESOURCE_SERVER_SCOPE		\N	4.29.1	\N	\N	2546741820
authz-3.4.0.CR1-resource-server-pk-change-part2-KEYCLOAK-6095	hmlnarik@redhat.com	META-INF/jpa-changelog-authz-3.4.0.CR1.xml	2025-11-07 20:19:08.589842	46	EXECUTED	9:b855e9b0a406b34fa323235a0cf4f640	customChange		\N	4.29.1	\N	\N	2546741820
authz-3.4.0.CR1-resource-server-pk-change-part3-fixed	glavoie@gmail.com	META-INF/jpa-changelog-authz-3.4.0.CR1.xml	2025-11-07 20:19:08.59575	47	MARK_RAN	9:51abbacd7b416c50c4421a8cabf7927e	dropIndex indexName=IDX_RES_SERV_POL_RES_SERV, tableName=RESOURCE_SERVER_POLICY; dropIndex indexName=IDX_RES_SRV_RES_RES_SRV, tableName=RESOURCE_SERVER_RESOURCE; dropIndex indexName=IDX_RES_SRV_SCOPE_RES_SRV, tableName=RESOURCE_SERVER_SCOPE		\N	4.29.1	\N	\N	2546741820
authz-3.4.0.CR1-resource-server-pk-change-part3-fixed-nodropindex	glavoie@gmail.com	META-INF/jpa-changelog-authz-3.4.0.CR1.xml	2025-11-07 20:19:08.874816	48	EXECUTED	9:bdc99e567b3398bac83263d375aad143	addNotNullConstraint columnName=RESOURCE_SERVER_CLIENT_ID, tableName=RESOURCE_SERVER_POLICY; addNotNullConstraint columnName=RESOURCE_SERVER_CLIENT_ID, tableName=RESOURCE_SERVER_RESOURCE; addNotNullConstraint columnName=RESOURCE_SERVER_CLIENT_ID, ...		\N	4.29.1	\N	\N	2546741820
authn-3.4.0.CR1-refresh-token-max-reuse	glavoie@gmail.com	META-INF/jpa-changelog-authz-3.4.0.CR1.xml	2025-11-07 20:19:08.890355	49	EXECUTED	9:d198654156881c46bfba39abd7769e69	addColumn tableName=REALM		\N	4.29.1	\N	\N	2546741820
3.4.0	keycloak	META-INF/jpa-changelog-3.4.0.xml	2025-11-07 20:19:08.958082	50	EXECUTED	9:cfdd8736332ccdd72c5256ccb42335db	addPrimaryKey constraintName=CONSTRAINT_REALM_DEFAULT_ROLES, tableName=REALM_DEFAULT_ROLES; addPrimaryKey constraintName=CONSTRAINT_COMPOSITE_ROLE, tableName=COMPOSITE_ROLE; addPrimaryKey constraintName=CONSTR_REALM_DEFAULT_GROUPS, tableName=REALM...		\N	4.29.1	\N	\N	2546741820
3.4.0-KEYCLOAK-5230	hmlnarik@redhat.com	META-INF/jpa-changelog-3.4.0.xml	2025-11-07 20:19:09.604783	51	EXECUTED	9:7c84de3d9bd84d7f077607c1a4dcb714	createIndex indexName=IDX_FU_ATTRIBUTE, tableName=FED_USER_ATTRIBUTE; createIndex indexName=IDX_FU_CONSENT, tableName=FED_USER_CONSENT; createIndex indexName=IDX_FU_CONSENT_RU, tableName=FED_USER_CONSENT; createIndex indexName=IDX_FU_CREDENTIAL, t...		\N	4.29.1	\N	\N	2546741820
3.4.1	psilva@redhat.com	META-INF/jpa-changelog-3.4.1.xml	2025-11-07 20:19:09.617516	52	EXECUTED	9:5a6bb36cbefb6a9d6928452c0852af2d	modifyDataType columnName=VALUE, tableName=CLIENT_ATTRIBUTES		\N	4.29.1	\N	\N	2546741820
3.4.2	keycloak	META-INF/jpa-changelog-3.4.2.xml	2025-11-07 20:19:09.629298	53	EXECUTED	9:8f23e334dbc59f82e0a328373ca6ced0	update tableName=REALM		\N	4.29.1	\N	\N	2546741820
3.4.2-KEYCLOAK-5172	mkanis@redhat.com	META-INF/jpa-changelog-3.4.2.xml	2025-11-07 20:19:09.643642	54	EXECUTED	9:9156214268f09d970cdf0e1564d866af	update tableName=CLIENT		\N	4.29.1	\N	\N	2546741820
4.0.0-KEYCLOAK-6335	bburke@redhat.com	META-INF/jpa-changelog-4.0.0.xml	2025-11-07 20:19:09.662499	55	EXECUTED	9:db806613b1ed154826c02610b7dbdf74	createTable tableName=CLIENT_AUTH_FLOW_BINDINGS; addPrimaryKey constraintName=C_CLI_FLOW_BIND, tableName=CLIENT_AUTH_FLOW_BINDINGS		\N	4.29.1	\N	\N	2546741820
4.0.0-CLEANUP-UNUSED-TABLE	bburke@redhat.com	META-INF/jpa-changelog-4.0.0.xml	2025-11-07 20:19:09.678208	56	EXECUTED	9:229a041fb72d5beac76bb94a5fa709de	dropTable tableName=CLIENT_IDENTITY_PROV_MAPPING		\N	4.29.1	\N	\N	2546741820
4.0.0-KEYCLOAK-6228	bburke@redhat.com	META-INF/jpa-changelog-4.0.0.xml	2025-11-07 20:19:09.782094	57	EXECUTED	9:079899dade9c1e683f26b2aa9ca6ff04	dropUniqueConstraint constraintName=UK_JKUWUVD56ONTGSUHOGM8UEWRT, tableName=USER_CONSENT; dropNotNullConstraint columnName=CLIENT_ID, tableName=USER_CONSENT; addColumn tableName=USER_CONSENT; addUniqueConstraint constraintName=UK_JKUWUVD56ONTGSUHO...		\N	4.29.1	\N	\N	2546741820
4.0.0-KEYCLOAK-5579-fixed	mposolda@redhat.com	META-INF/jpa-changelog-4.0.0.xml	2025-11-07 20:19:10.485878	58	EXECUTED	9:139b79bcbbfe903bb1c2d2a4dbf001d9	dropForeignKeyConstraint baseTableName=CLIENT_TEMPLATE_ATTRIBUTES, constraintName=FK_CL_TEMPL_ATTR_TEMPL; renameTable newTableName=CLIENT_SCOPE_ATTRIBUTES, oldTableName=CLIENT_TEMPLATE_ATTRIBUTES; renameColumn newColumnName=SCOPE_ID, oldColumnName...		\N	4.29.1	\N	\N	2546741820
authz-4.0.0.CR1	psilva@redhat.com	META-INF/jpa-changelog-authz-4.0.0.CR1.xml	2025-11-07 20:19:10.529053	59	EXECUTED	9:b55738ad889860c625ba2bf483495a04	createTable tableName=RESOURCE_SERVER_PERM_TICKET; addPrimaryKey constraintName=CONSTRAINT_FAPMT, tableName=RESOURCE_SERVER_PERM_TICKET; addForeignKeyConstraint baseTableName=RESOURCE_SERVER_PERM_TICKET, constraintName=FK_FRSRHO213XCX4WNKOG82SSPMT...		\N	4.29.1	\N	\N	2546741820
authz-4.0.0.Beta3	psilva@redhat.com	META-INF/jpa-changelog-authz-4.0.0.Beta3.xml	2025-11-07 20:19:10.546038	60	EXECUTED	9:e0057eac39aa8fc8e09ac6cfa4ae15fe	addColumn tableName=RESOURCE_SERVER_POLICY; addColumn tableName=RESOURCE_SERVER_PERM_TICKET; addForeignKeyConstraint baseTableName=RESOURCE_SERVER_PERM_TICKET, constraintName=FK_FRSRPO2128CX4WNKOG82SSRFY, referencedTableName=RESOURCE_SERVER_POLICY		\N	4.29.1	\N	\N	2546741820
authz-4.2.0.Final	mhajas@redhat.com	META-INF/jpa-changelog-authz-4.2.0.Final.xml	2025-11-07 20:19:10.569049	61	EXECUTED	9:42a33806f3a0443fe0e7feeec821326c	createTable tableName=RESOURCE_URIS; addForeignKeyConstraint baseTableName=RESOURCE_URIS, constraintName=FK_RESOURCE_SERVER_URIS, referencedTableName=RESOURCE_SERVER_RESOURCE; customChange; dropColumn columnName=URI, tableName=RESOURCE_SERVER_RESO...		\N	4.29.1	\N	\N	2546741820
authz-4.2.0.Final-KEYCLOAK-9944	hmlnarik@redhat.com	META-INF/jpa-changelog-authz-4.2.0.Final.xml	2025-11-07 20:19:10.581649	62	EXECUTED	9:9968206fca46eecc1f51db9c024bfe56	addPrimaryKey constraintName=CONSTRAINT_RESOUR_URIS_PK, tableName=RESOURCE_URIS		\N	4.29.1	\N	\N	2546741820
4.2.0-KEYCLOAK-6313	wadahiro@gmail.com	META-INF/jpa-changelog-4.2.0.xml	2025-11-07 20:19:10.59304	63	EXECUTED	9:92143a6daea0a3f3b8f598c97ce55c3d	addColumn tableName=REQUIRED_ACTION_PROVIDER		\N	4.29.1	\N	\N	2546741820
4.3.0-KEYCLOAK-7984	wadahiro@gmail.com	META-INF/jpa-changelog-4.3.0.xml	2025-11-07 20:19:10.60363	64	EXECUTED	9:82bab26a27195d889fb0429003b18f40	update tableName=REQUIRED_ACTION_PROVIDER		\N	4.29.1	\N	\N	2546741820
4.6.0-KEYCLOAK-7950	psilva@redhat.com	META-INF/jpa-changelog-4.6.0.xml	2025-11-07 20:19:10.614229	65	EXECUTED	9:e590c88ddc0b38b0ae4249bbfcb5abc3	update tableName=RESOURCE_SERVER_RESOURCE		\N	4.29.1	\N	\N	2546741820
4.6.0-KEYCLOAK-8377	keycloak	META-INF/jpa-changelog-4.6.0.xml	2025-11-07 20:19:10.686074	66	EXECUTED	9:5c1f475536118dbdc38d5d7977950cc0	createTable tableName=ROLE_ATTRIBUTE; addPrimaryKey constraintName=CONSTRAINT_ROLE_ATTRIBUTE_PK, tableName=ROLE_ATTRIBUTE; addForeignKeyConstraint baseTableName=ROLE_ATTRIBUTE, constraintName=FK_ROLE_ATTRIBUTE_ID, referencedTableName=KEYCLOAK_ROLE...		\N	4.29.1	\N	\N	2546741820
4.6.0-KEYCLOAK-8555	gideonray@gmail.com	META-INF/jpa-changelog-4.6.0.xml	2025-11-07 20:19:10.752706	67	EXECUTED	9:e7c9f5f9c4d67ccbbcc215440c718a17	createIndex indexName=IDX_COMPONENT_PROVIDER_TYPE, tableName=COMPONENT		\N	4.29.1	\N	\N	2546741820
4.7.0-KEYCLOAK-1267	sguilhen@redhat.com	META-INF/jpa-changelog-4.7.0.xml	2025-11-07 20:19:10.76665	68	EXECUTED	9:88e0bfdda924690d6f4e430c53447dd5	addColumn tableName=REALM		\N	4.29.1	\N	\N	2546741820
4.7.0-KEYCLOAK-7275	keycloak	META-INF/jpa-changelog-4.7.0.xml	2025-11-07 20:19:10.848542	69	EXECUTED	9:f53177f137e1c46b6a88c59ec1cb5218	renameColumn newColumnName=CREATED_ON, oldColumnName=LAST_SESSION_REFRESH, tableName=OFFLINE_USER_SESSION; addNotNullConstraint columnName=CREATED_ON, tableName=OFFLINE_USER_SESSION; addColumn tableName=OFFLINE_USER_SESSION; customChange; createIn...		\N	4.29.1	\N	\N	2546741820
4.8.0-KEYCLOAK-8835	sguilhen@redhat.com	META-INF/jpa-changelog-4.8.0.xml	2025-11-07 20:19:10.873153	70	EXECUTED	9:a74d33da4dc42a37ec27121580d1459f	addNotNullConstraint columnName=SSO_MAX_LIFESPAN_REMEMBER_ME, tableName=REALM; addNotNullConstraint columnName=SSO_IDLE_TIMEOUT_REMEMBER_ME, tableName=REALM		\N	4.29.1	\N	\N	2546741820
authz-7.0.0-KEYCLOAK-10443	psilva@redhat.com	META-INF/jpa-changelog-authz-7.0.0.xml	2025-11-07 20:19:10.887374	71	EXECUTED	9:fd4ade7b90c3b67fae0bfcfcb42dfb5f	addColumn tableName=RESOURCE_SERVER		\N	4.29.1	\N	\N	2546741820
8.0.0-adding-credential-columns	keycloak	META-INF/jpa-changelog-8.0.0.xml	2025-11-07 20:19:10.91915	72	EXECUTED	9:aa072ad090bbba210d8f18781b8cebf4	addColumn tableName=CREDENTIAL; addColumn tableName=FED_USER_CREDENTIAL		\N	4.29.1	\N	\N	2546741820
8.0.0-updating-credential-data-not-oracle-fixed	keycloak	META-INF/jpa-changelog-8.0.0.xml	2025-11-07 20:19:10.946323	73	EXECUTED	9:1ae6be29bab7c2aa376f6983b932be37	update tableName=CREDENTIAL; update tableName=CREDENTIAL; update tableName=CREDENTIAL; update tableName=FED_USER_CREDENTIAL; update tableName=FED_USER_CREDENTIAL; update tableName=FED_USER_CREDENTIAL		\N	4.29.1	\N	\N	2546741820
8.0.0-updating-credential-data-oracle-fixed	keycloak	META-INF/jpa-changelog-8.0.0.xml	2025-11-07 20:19:10.953994	74	MARK_RAN	9:14706f286953fc9a25286dbd8fb30d97	update tableName=CREDENTIAL; update tableName=CREDENTIAL; update tableName=CREDENTIAL; update tableName=FED_USER_CREDENTIAL; update tableName=FED_USER_CREDENTIAL; update tableName=FED_USER_CREDENTIAL		\N	4.29.1	\N	\N	2546741820
8.0.0-credential-cleanup-fixed	keycloak	META-INF/jpa-changelog-8.0.0.xml	2025-11-07 20:19:11.029456	75	EXECUTED	9:2b9cc12779be32c5b40e2e67711a218b	dropDefaultValue columnName=COUNTER, tableName=CREDENTIAL; dropDefaultValue columnName=DIGITS, tableName=CREDENTIAL; dropDefaultValue columnName=PERIOD, tableName=CREDENTIAL; dropDefaultValue columnName=ALGORITHM, tableName=CREDENTIAL; dropColumn ...		\N	4.29.1	\N	\N	2546741820
8.0.0-resource-tag-support	keycloak	META-INF/jpa-changelog-8.0.0.xml	2025-11-07 20:19:11.101845	76	EXECUTED	9:91fa186ce7a5af127a2d7a91ee083cc5	addColumn tableName=MIGRATION_MODEL; createIndex indexName=IDX_UPDATE_TIME, tableName=MIGRATION_MODEL		\N	4.29.1	\N	\N	2546741820
9.0.0-always-display-client	keycloak	META-INF/jpa-changelog-9.0.0.xml	2025-11-07 20:19:11.116483	77	EXECUTED	9:6335e5c94e83a2639ccd68dd24e2e5ad	addColumn tableName=CLIENT		\N	4.29.1	\N	\N	2546741820
9.0.0-drop-constraints-for-column-increase	keycloak	META-INF/jpa-changelog-9.0.0.xml	2025-11-07 20:19:11.122091	78	MARK_RAN	9:6bdb5658951e028bfe16fa0a8228b530	dropUniqueConstraint constraintName=UK_FRSR6T700S9V50BU18WS5PMT, tableName=RESOURCE_SERVER_PERM_TICKET; dropUniqueConstraint constraintName=UK_FRSR6T700S9V50BU18WS5HA6, tableName=RESOURCE_SERVER_RESOURCE; dropPrimaryKey constraintName=CONSTRAINT_O...		\N	4.29.1	\N	\N	2546741820
9.0.0-increase-column-size-federated-fk	keycloak	META-INF/jpa-changelog-9.0.0.xml	2025-11-07 20:19:11.162556	79	EXECUTED	9:d5bc15a64117ccad481ce8792d4c608f	modifyDataType columnName=CLIENT_ID, tableName=FED_USER_CONSENT; modifyDataType columnName=CLIENT_REALM_CONSTRAINT, tableName=KEYCLOAK_ROLE; modifyDataType columnName=OWNER, tableName=RESOURCE_SERVER_POLICY; modifyDataType columnName=CLIENT_ID, ta...		\N	4.29.1	\N	\N	2546741820
9.0.0-recreate-constraints-after-column-increase	keycloak	META-INF/jpa-changelog-9.0.0.xml	2025-11-07 20:19:11.168826	80	MARK_RAN	9:077cba51999515f4d3e7ad5619ab592c	addNotNullConstraint columnName=CLIENT_ID, tableName=OFFLINE_CLIENT_SESSION; addNotNullConstraint columnName=OWNER, tableName=RESOURCE_SERVER_PERM_TICKET; addNotNullConstraint columnName=REQUESTER, tableName=RESOURCE_SERVER_PERM_TICKET; addNotNull...		\N	4.29.1	\N	\N	2546741820
9.0.1-add-index-to-client.client_id	keycloak	META-INF/jpa-changelog-9.0.1.xml	2025-11-07 20:19:11.24022	81	EXECUTED	9:be969f08a163bf47c6b9e9ead8ac2afb	createIndex indexName=IDX_CLIENT_ID, tableName=CLIENT		\N	4.29.1	\N	\N	2546741820
9.0.1-KEYCLOAK-12579-drop-constraints	keycloak	META-INF/jpa-changelog-9.0.1.xml	2025-11-07 20:19:11.245796	82	MARK_RAN	9:6d3bb4408ba5a72f39bd8a0b301ec6e3	dropUniqueConstraint constraintName=SIBLING_NAMES, tableName=KEYCLOAK_GROUP		\N	4.29.1	\N	\N	2546741820
9.0.1-KEYCLOAK-12579-add-not-null-constraint	keycloak	META-INF/jpa-changelog-9.0.1.xml	2025-11-07 20:19:11.26229	83	EXECUTED	9:966bda61e46bebf3cc39518fbed52fa7	addNotNullConstraint columnName=PARENT_GROUP, tableName=KEYCLOAK_GROUP		\N	4.29.1	\N	\N	2546741820
9.0.1-KEYCLOAK-12579-recreate-constraints	keycloak	META-INF/jpa-changelog-9.0.1.xml	2025-11-07 20:19:11.268683	84	MARK_RAN	9:8dcac7bdf7378e7d823cdfddebf72fda	addUniqueConstraint constraintName=SIBLING_NAMES, tableName=KEYCLOAK_GROUP		\N	4.29.1	\N	\N	2546741820
9.0.1-add-index-to-events	keycloak	META-INF/jpa-changelog-9.0.1.xml	2025-11-07 20:19:11.338058	85	EXECUTED	9:7d93d602352a30c0c317e6a609b56599	createIndex indexName=IDX_EVENT_TIME, tableName=EVENT_ENTITY		\N	4.29.1	\N	\N	2546741820
map-remove-ri	keycloak	META-INF/jpa-changelog-11.0.0.xml	2025-11-07 20:19:11.353601	86	EXECUTED	9:71c5969e6cdd8d7b6f47cebc86d37627	dropForeignKeyConstraint baseTableName=REALM, constraintName=FK_TRAF444KK6QRKMS7N56AIWQ5Y; dropForeignKeyConstraint baseTableName=KEYCLOAK_ROLE, constraintName=FK_KJHO5LE2C0RAL09FL8CM9WFW9		\N	4.29.1	\N	\N	2546741820
map-remove-ri	keycloak	META-INF/jpa-changelog-12.0.0.xml	2025-11-07 20:19:11.379314	87	EXECUTED	9:a9ba7d47f065f041b7da856a81762021	dropForeignKeyConstraint baseTableName=REALM_DEFAULT_GROUPS, constraintName=FK_DEF_GROUPS_GROUP; dropForeignKeyConstraint baseTableName=REALM_DEFAULT_ROLES, constraintName=FK_H4WPD7W4HSOOLNI3H0SW7BTJE; dropForeignKeyConstraint baseTableName=CLIENT...		\N	4.29.1	\N	\N	2546741820
12.1.0-add-realm-localization-table	keycloak	META-INF/jpa-changelog-12.0.0.xml	2025-11-07 20:19:11.396011	88	EXECUTED	9:fffabce2bc01e1a8f5110d5278500065	createTable tableName=REALM_LOCALIZATIONS; addPrimaryKey tableName=REALM_LOCALIZATIONS		\N	4.29.1	\N	\N	2546741820
default-roles	keycloak	META-INF/jpa-changelog-13.0.0.xml	2025-11-07 20:19:11.415136	89	EXECUTED	9:fa8a5b5445e3857f4b010bafb5009957	addColumn tableName=REALM; customChange		\N	4.29.1	\N	\N	2546741820
default-roles-cleanup	keycloak	META-INF/jpa-changelog-13.0.0.xml	2025-11-07 20:19:11.430055	90	EXECUTED	9:67ac3241df9a8582d591c5ed87125f39	dropTable tableName=REALM_DEFAULT_ROLES; dropTable tableName=CLIENT_DEFAULT_ROLES		\N	4.29.1	\N	\N	2546741820
13.0.0-KEYCLOAK-16844	keycloak	META-INF/jpa-changelog-13.0.0.xml	2025-11-07 20:19:11.501807	91	EXECUTED	9:ad1194d66c937e3ffc82386c050ba089	createIndex indexName=IDX_OFFLINE_USS_PRELOAD, tableName=OFFLINE_USER_SESSION		\N	4.29.1	\N	\N	2546741820
map-remove-ri-13.0.0	keycloak	META-INF/jpa-changelog-13.0.0.xml	2025-11-07 20:19:11.525533	92	EXECUTED	9:d9be619d94af5a2f5d07b9f003543b91	dropForeignKeyConstraint baseTableName=DEFAULT_CLIENT_SCOPE, constraintName=FK_R_DEF_CLI_SCOPE_SCOPE; dropForeignKeyConstraint baseTableName=CLIENT_SCOPE_CLIENT, constraintName=FK_C_CLI_SCOPE_SCOPE; dropForeignKeyConstraint baseTableName=CLIENT_SC...		\N	4.29.1	\N	\N	2546741820
13.0.0-KEYCLOAK-17992-drop-constraints	keycloak	META-INF/jpa-changelog-13.0.0.xml	2025-11-07 20:19:11.530612	93	MARK_RAN	9:544d201116a0fcc5a5da0925fbbc3bde	dropPrimaryKey constraintName=C_CLI_SCOPE_BIND, tableName=CLIENT_SCOPE_CLIENT; dropIndex indexName=IDX_CLSCOPE_CL, tableName=CLIENT_SCOPE_CLIENT; dropIndex indexName=IDX_CL_CLSCOPE, tableName=CLIENT_SCOPE_CLIENT		\N	4.29.1	\N	\N	2546741820
13.0.0-increase-column-size-federated	keycloak	META-INF/jpa-changelog-13.0.0.xml	2025-11-07 20:19:11.548319	94	EXECUTED	9:43c0c1055b6761b4b3e89de76d612ccf	modifyDataType columnName=CLIENT_ID, tableName=CLIENT_SCOPE_CLIENT; modifyDataType columnName=SCOPE_ID, tableName=CLIENT_SCOPE_CLIENT		\N	4.29.1	\N	\N	2546741820
13.0.0-KEYCLOAK-17992-recreate-constraints	keycloak	META-INF/jpa-changelog-13.0.0.xml	2025-11-07 20:19:11.55357	95	MARK_RAN	9:8bd711fd0330f4fe980494ca43ab1139	addNotNullConstraint columnName=CLIENT_ID, tableName=CLIENT_SCOPE_CLIENT; addNotNullConstraint columnName=SCOPE_ID, tableName=CLIENT_SCOPE_CLIENT; addPrimaryKey constraintName=C_CLI_SCOPE_BIND, tableName=CLIENT_SCOPE_CLIENT; createIndex indexName=...		\N	4.29.1	\N	\N	2546741820
json-string-accomodation-fixed	keycloak	META-INF/jpa-changelog-13.0.0.xml	2025-11-07 20:19:11.572382	96	EXECUTED	9:e07d2bc0970c348bb06fb63b1f82ddbf	addColumn tableName=REALM_ATTRIBUTE; update tableName=REALM_ATTRIBUTE; dropColumn columnName=VALUE, tableName=REALM_ATTRIBUTE; renameColumn newColumnName=VALUE, oldColumnName=VALUE_NEW, tableName=REALM_ATTRIBUTE		\N	4.29.1	\N	\N	2546741820
14.0.0-KEYCLOAK-11019	keycloak	META-INF/jpa-changelog-14.0.0.xml	2025-11-07 20:19:11.739433	97	EXECUTED	9:24fb8611e97f29989bea412aa38d12b7	createIndex indexName=IDX_OFFLINE_CSS_PRELOAD, tableName=OFFLINE_CLIENT_SESSION; createIndex indexName=IDX_OFFLINE_USS_BY_USER, tableName=OFFLINE_USER_SESSION; createIndex indexName=IDX_OFFLINE_USS_BY_USERSESS, tableName=OFFLINE_USER_SESSION		\N	4.29.1	\N	\N	2546741820
14.0.0-KEYCLOAK-18286	keycloak	META-INF/jpa-changelog-14.0.0.xml	2025-11-07 20:19:11.745205	98	MARK_RAN	9:259f89014ce2506ee84740cbf7163aa7	createIndex indexName=IDX_CLIENT_ATT_BY_NAME_VALUE, tableName=CLIENT_ATTRIBUTES		\N	4.29.1	\N	\N	2546741820
14.0.0-KEYCLOAK-18286-revert	keycloak	META-INF/jpa-changelog-14.0.0.xml	2025-11-07 20:19:11.768666	99	MARK_RAN	9:04baaf56c116ed19951cbc2cca584022	dropIndex indexName=IDX_CLIENT_ATT_BY_NAME_VALUE, tableName=CLIENT_ATTRIBUTES		\N	4.29.1	\N	\N	2546741820
14.0.0-KEYCLOAK-18286-supported-dbs	keycloak	META-INF/jpa-changelog-14.0.0.xml	2025-11-07 20:19:11.839727	100	EXECUTED	9:60ca84a0f8c94ec8c3504a5a3bc88ee8	createIndex indexName=IDX_CLIENT_ATT_BY_NAME_VALUE, tableName=CLIENT_ATTRIBUTES		\N	4.29.1	\N	\N	2546741820
14.0.0-KEYCLOAK-18286-unsupported-dbs	keycloak	META-INF/jpa-changelog-14.0.0.xml	2025-11-07 20:19:11.845326	101	MARK_RAN	9:d3d977031d431db16e2c181ce49d73e9	createIndex indexName=IDX_CLIENT_ATT_BY_NAME_VALUE, tableName=CLIENT_ATTRIBUTES		\N	4.29.1	\N	\N	2546741820
KEYCLOAK-17267-add-index-to-user-attributes	keycloak	META-INF/jpa-changelog-14.0.0.xml	2025-11-07 20:19:11.920096	102	EXECUTED	9:0b305d8d1277f3a89a0a53a659ad274c	createIndex indexName=IDX_USER_ATTRIBUTE_NAME, tableName=USER_ATTRIBUTE		\N	4.29.1	\N	\N	2546741820
KEYCLOAK-18146-add-saml-art-binding-identifier	keycloak	META-INF/jpa-changelog-14.0.0.xml	2025-11-07 20:19:11.93863	103	EXECUTED	9:2c374ad2cdfe20e2905a84c8fac48460	customChange		\N	4.29.1	\N	\N	2546741820
15.0.0-KEYCLOAK-18467	keycloak	META-INF/jpa-changelog-15.0.0.xml	2025-11-07 20:19:11.960835	104	EXECUTED	9:47a760639ac597360a8219f5b768b4de	addColumn tableName=REALM_LOCALIZATIONS; update tableName=REALM_LOCALIZATIONS; dropColumn columnName=TEXTS, tableName=REALM_LOCALIZATIONS; renameColumn newColumnName=TEXTS, oldColumnName=TEXTS_NEW, tableName=REALM_LOCALIZATIONS; addNotNullConstrai...		\N	4.29.1	\N	\N	2546741820
17.0.0-9562	keycloak	META-INF/jpa-changelog-17.0.0.xml	2025-11-07 20:19:12.030731	105	EXECUTED	9:a6272f0576727dd8cad2522335f5d99e	createIndex indexName=IDX_USER_SERVICE_ACCOUNT, tableName=USER_ENTITY		\N	4.29.1	\N	\N	2546741820
18.0.0-10625-IDX_ADMIN_EVENT_TIME	keycloak	META-INF/jpa-changelog-18.0.0.xml	2025-11-07 20:19:12.101136	106	EXECUTED	9:015479dbd691d9cc8669282f4828c41d	createIndex indexName=IDX_ADMIN_EVENT_TIME, tableName=ADMIN_EVENT_ENTITY		\N	4.29.1	\N	\N	2546741820
18.0.15-30992-index-consent	keycloak	META-INF/jpa-changelog-18.0.15.xml	2025-11-07 20:19:12.185939	107	EXECUTED	9:80071ede7a05604b1f4906f3bf3b00f0	createIndex indexName=IDX_USCONSENT_SCOPE_ID, tableName=USER_CONSENT_CLIENT_SCOPE		\N	4.29.1	\N	\N	2546741820
19.0.0-10135	keycloak	META-INF/jpa-changelog-19.0.0.xml	2025-11-07 20:19:12.205409	108	EXECUTED	9:9518e495fdd22f78ad6425cc30630221	customChange		\N	4.29.1	\N	\N	2546741820
20.0.0-12964-supported-dbs	keycloak	META-INF/jpa-changelog-20.0.0.xml	2025-11-07 20:19:12.276183	109	EXECUTED	9:e5f243877199fd96bcc842f27a1656ac	createIndex indexName=IDX_GROUP_ATT_BY_NAME_VALUE, tableName=GROUP_ATTRIBUTE		\N	4.29.1	\N	\N	2546741820
20.0.0-12964-unsupported-dbs	keycloak	META-INF/jpa-changelog-20.0.0.xml	2025-11-07 20:19:12.281747	110	MARK_RAN	9:1a6fcaa85e20bdeae0a9ce49b41946a5	createIndex indexName=IDX_GROUP_ATT_BY_NAME_VALUE, tableName=GROUP_ATTRIBUTE		\N	4.29.1	\N	\N	2546741820
client-attributes-string-accomodation-fixed	keycloak	META-INF/jpa-changelog-20.0.0.xml	2025-11-07 20:19:12.300192	111	EXECUTED	9:3f332e13e90739ed0c35b0b25b7822ca	addColumn tableName=CLIENT_ATTRIBUTES; update tableName=CLIENT_ATTRIBUTES; dropColumn columnName=VALUE, tableName=CLIENT_ATTRIBUTES; renameColumn newColumnName=VALUE, oldColumnName=VALUE_NEW, tableName=CLIENT_ATTRIBUTES		\N	4.29.1	\N	\N	2546741820
21.0.2-17277	keycloak	META-INF/jpa-changelog-21.0.2.xml	2025-11-07 20:19:12.315207	112	EXECUTED	9:7ee1f7a3fb8f5588f171fb9a6ab623c0	customChange		\N	4.29.1	\N	\N	2546741820
21.1.0-19404	keycloak	META-INF/jpa-changelog-21.1.0.xml	2025-11-07 20:19:12.339835	113	EXECUTED	9:3d7e830b52f33676b9d64f7f2b2ea634	modifyDataType columnName=DECISION_STRATEGY, tableName=RESOURCE_SERVER_POLICY; modifyDataType columnName=LOGIC, tableName=RESOURCE_SERVER_POLICY; modifyDataType columnName=POLICY_ENFORCE_MODE, tableName=RESOURCE_SERVER		\N	4.29.1	\N	\N	2546741820
21.1.0-19404-2	keycloak	META-INF/jpa-changelog-21.1.0.xml	2025-11-07 20:19:12.346213	114	MARK_RAN	9:627d032e3ef2c06c0e1f73d2ae25c26c	addColumn tableName=RESOURCE_SERVER_POLICY; update tableName=RESOURCE_SERVER_POLICY; dropColumn columnName=DECISION_STRATEGY, tableName=RESOURCE_SERVER_POLICY; renameColumn newColumnName=DECISION_STRATEGY, oldColumnName=DECISION_STRATEGY_NEW, tabl...		\N	4.29.1	\N	\N	2546741820
22.0.0-17484-updated	keycloak	META-INF/jpa-changelog-22.0.0.xml	2025-11-07 20:19:12.363377	115	EXECUTED	9:90af0bfd30cafc17b9f4d6eccd92b8b3	customChange		\N	4.29.1	\N	\N	2546741820
22.0.5-24031	keycloak	META-INF/jpa-changelog-22.0.0.xml	2025-11-07 20:19:12.368246	116	MARK_RAN	9:a60d2d7b315ec2d3eba9e2f145f9df28	customChange		\N	4.29.1	\N	\N	2546741820
23.0.0-12062	keycloak	META-INF/jpa-changelog-23.0.0.xml	2025-11-07 20:19:12.386763	117	EXECUTED	9:2168fbe728fec46ae9baf15bf80927b8	addColumn tableName=COMPONENT_CONFIG; update tableName=COMPONENT_CONFIG; dropColumn columnName=VALUE, tableName=COMPONENT_CONFIG; renameColumn newColumnName=VALUE, oldColumnName=VALUE_NEW, tableName=COMPONENT_CONFIG		\N	4.29.1	\N	\N	2546741820
23.0.0-17258	keycloak	META-INF/jpa-changelog-23.0.0.xml	2025-11-07 20:19:12.397855	118	EXECUTED	9:36506d679a83bbfda85a27ea1864dca8	addColumn tableName=EVENT_ENTITY		\N	4.29.1	\N	\N	2546741820
24.0.0-9758	keycloak	META-INF/jpa-changelog-24.0.0.xml	2025-11-07 20:19:12.623622	119	EXECUTED	9:502c557a5189f600f0f445a9b49ebbce	addColumn tableName=USER_ATTRIBUTE; addColumn tableName=FED_USER_ATTRIBUTE; createIndex indexName=USER_ATTR_LONG_VALUES, tableName=USER_ATTRIBUTE; createIndex indexName=FED_USER_ATTR_LONG_VALUES, tableName=FED_USER_ATTRIBUTE; createIndex indexName...		\N	4.29.1	\N	\N	2546741820
24.0.0-9758-2	keycloak	META-INF/jpa-changelog-24.0.0.xml	2025-11-07 20:19:12.638702	120	EXECUTED	9:bf0fdee10afdf597a987adbf291db7b2	customChange		\N	4.29.1	\N	\N	2546741820
24.0.0-26618-drop-index-if-present	keycloak	META-INF/jpa-changelog-24.0.0.xml	2025-11-07 20:19:12.654167	121	MARK_RAN	9:04baaf56c116ed19951cbc2cca584022	dropIndex indexName=IDX_CLIENT_ATT_BY_NAME_VALUE, tableName=CLIENT_ATTRIBUTES		\N	4.29.1	\N	\N	2546741820
24.0.0-26618-reindex	keycloak	META-INF/jpa-changelog-24.0.0.xml	2025-11-07 20:19:12.720002	122	EXECUTED	9:08707c0f0db1cef6b352db03a60edc7f	createIndex indexName=IDX_CLIENT_ATT_BY_NAME_VALUE, tableName=CLIENT_ATTRIBUTES		\N	4.29.1	\N	\N	2546741820
24.0.2-27228	keycloak	META-INF/jpa-changelog-24.0.2.xml	2025-11-07 20:19:12.736106	123	EXECUTED	9:eaee11f6b8aa25d2cc6a84fb86fc6238	customChange		\N	4.29.1	\N	\N	2546741820
24.0.2-27967-drop-index-if-present	keycloak	META-INF/jpa-changelog-24.0.2.xml	2025-11-07 20:19:12.740847	124	MARK_RAN	9:04baaf56c116ed19951cbc2cca584022	dropIndex indexName=IDX_CLIENT_ATT_BY_NAME_VALUE, tableName=CLIENT_ATTRIBUTES		\N	4.29.1	\N	\N	2546741820
24.0.2-27967-reindex	keycloak	META-INF/jpa-changelog-24.0.2.xml	2025-11-07 20:19:12.747148	125	MARK_RAN	9:d3d977031d431db16e2c181ce49d73e9	createIndex indexName=IDX_CLIENT_ATT_BY_NAME_VALUE, tableName=CLIENT_ATTRIBUTES		\N	4.29.1	\N	\N	2546741820
25.0.0-28265-tables	keycloak	META-INF/jpa-changelog-25.0.0.xml	2025-11-07 20:19:12.765407	126	EXECUTED	9:deda2df035df23388af95bbd36c17cef	addColumn tableName=OFFLINE_USER_SESSION; addColumn tableName=OFFLINE_CLIENT_SESSION		\N	4.29.1	\N	\N	2546741820
25.0.0-28265-index-creation	keycloak	META-INF/jpa-changelog-25.0.0.xml	2025-11-07 20:19:12.824226	127	EXECUTED	9:3e96709818458ae49f3c679ae58d263a	createIndex indexName=IDX_OFFLINE_USS_BY_LAST_SESSION_REFRESH, tableName=OFFLINE_USER_SESSION		\N	4.29.1	\N	\N	2546741820
25.0.0-28265-index-cleanup-uss-createdon	keycloak	META-INF/jpa-changelog-25.0.0.xml	2025-11-07 20:19:12.925775	128	EXECUTED	9:78ab4fc129ed5e8265dbcc3485fba92f	dropIndex indexName=IDX_OFFLINE_USS_CREATEDON, tableName=OFFLINE_USER_SESSION		\N	4.29.1	\N	\N	2546741820
25.0.0-28265-index-cleanup-uss-preload	keycloak	META-INF/jpa-changelog-25.0.0.xml	2025-11-07 20:19:13.010543	129	EXECUTED	9:de5f7c1f7e10994ed8b62e621d20eaab	dropIndex indexName=IDX_OFFLINE_USS_PRELOAD, tableName=OFFLINE_USER_SESSION		\N	4.29.1	\N	\N	2546741820
25.0.0-28265-index-cleanup-uss-by-usersess	keycloak	META-INF/jpa-changelog-25.0.0.xml	2025-11-07 20:19:13.097179	130	EXECUTED	9:6eee220d024e38e89c799417ec33667f	dropIndex indexName=IDX_OFFLINE_USS_BY_USERSESS, tableName=OFFLINE_USER_SESSION		\N	4.29.1	\N	\N	2546741820
25.0.0-28265-index-cleanup-css-preload	keycloak	META-INF/jpa-changelog-25.0.0.xml	2025-11-07 20:19:13.159251	131	EXECUTED	9:5411d2fb2891d3e8d63ddb55dfa3c0c9	dropIndex indexName=IDX_OFFLINE_CSS_PRELOAD, tableName=OFFLINE_CLIENT_SESSION		\N	4.29.1	\N	\N	2546741820
25.0.0-28265-index-2-mysql	keycloak	META-INF/jpa-changelog-25.0.0.xml	2025-11-07 20:19:13.16523	132	MARK_RAN	9:b7ef76036d3126bb83c2423bf4d449d6	createIndex indexName=IDX_OFFLINE_USS_BY_BROKER_SESSION_ID, tableName=OFFLINE_USER_SESSION		\N	4.29.1	\N	\N	2546741820
25.0.0-28265-index-2-not-mysql	keycloak	META-INF/jpa-changelog-25.0.0.xml	2025-11-07 20:19:13.245183	133	EXECUTED	9:23396cf51ab8bc1ae6f0cac7f9f6fcf7	createIndex indexName=IDX_OFFLINE_USS_BY_BROKER_SESSION_ID, tableName=OFFLINE_USER_SESSION		\N	4.29.1	\N	\N	2546741820
25.0.0-org	keycloak	META-INF/jpa-changelog-25.0.0.xml	2025-11-07 20:19:13.273001	134	EXECUTED	9:5c859965c2c9b9c72136c360649af157	createTable tableName=ORG; addUniqueConstraint constraintName=UK_ORG_NAME, tableName=ORG; addUniqueConstraint constraintName=UK_ORG_GROUP, tableName=ORG; createTable tableName=ORG_DOMAIN		\N	4.29.1	\N	\N	2546741820
unique-consentuser	keycloak	META-INF/jpa-changelog-25.0.0.xml	2025-11-07 20:19:13.305632	135	EXECUTED	9:5857626a2ea8767e9a6c66bf3a2cb32f	customChange; dropUniqueConstraint constraintName=UK_JKUWUVD56ONTGSUHOGM8UEWRT, tableName=USER_CONSENT; addUniqueConstraint constraintName=UK_LOCAL_CONSENT, tableName=USER_CONSENT; addUniqueConstraint constraintName=UK_EXTERNAL_CONSENT, tableName=...		\N	4.29.1	\N	\N	2546741820
unique-consentuser-mysql	keycloak	META-INF/jpa-changelog-25.0.0.xml	2025-11-07 20:19:13.311039	136	MARK_RAN	9:b79478aad5adaa1bc428e31563f55e8e	customChange; dropUniqueConstraint constraintName=UK_JKUWUVD56ONTGSUHOGM8UEWRT, tableName=USER_CONSENT; addUniqueConstraint constraintName=UK_LOCAL_CONSENT, tableName=USER_CONSENT; addUniqueConstraint constraintName=UK_EXTERNAL_CONSENT, tableName=...		\N	4.29.1	\N	\N	2546741820
25.0.0-28861-index-creation	keycloak	META-INF/jpa-changelog-25.0.0.xml	2025-11-07 20:19:13.444193	137	EXECUTED	9:b9acb58ac958d9ada0fe12a5d4794ab1	createIndex indexName=IDX_PERM_TICKET_REQUESTER, tableName=RESOURCE_SERVER_PERM_TICKET; createIndex indexName=IDX_PERM_TICKET_OWNER, tableName=RESOURCE_SERVER_PERM_TICKET		\N	4.29.1	\N	\N	2546741820
26.0.0-org-alias	keycloak	META-INF/jpa-changelog-26.0.0.xml	2025-11-07 20:19:13.466076	138	EXECUTED	9:6ef7d63e4412b3c2d66ed179159886a4	addColumn tableName=ORG; update tableName=ORG; addNotNullConstraint columnName=ALIAS, tableName=ORG; addUniqueConstraint constraintName=UK_ORG_ALIAS, tableName=ORG		\N	4.29.1	\N	\N	2546741820
26.0.0-org-group	keycloak	META-INF/jpa-changelog-26.0.0.xml	2025-11-07 20:19:13.497114	139	EXECUTED	9:da8e8087d80ef2ace4f89d8c5b9ca223	addColumn tableName=KEYCLOAK_GROUP; update tableName=KEYCLOAK_GROUP; addNotNullConstraint columnName=TYPE, tableName=KEYCLOAK_GROUP; customChange		\N	4.29.1	\N	\N	2546741820
26.0.0-org-indexes	keycloak	META-INF/jpa-changelog-26.0.0.xml	2025-11-07 20:19:13.583517	140	EXECUTED	9:79b05dcd610a8c7f25ec05135eec0857	createIndex indexName=IDX_ORG_DOMAIN_ORG_ID, tableName=ORG_DOMAIN		\N	4.29.1	\N	\N	2546741820
26.0.0-org-group-membership	keycloak	META-INF/jpa-changelog-26.0.0.xml	2025-11-07 20:19:13.604737	141	EXECUTED	9:a6ace2ce583a421d89b01ba2a28dc2d4	addColumn tableName=USER_GROUP_MEMBERSHIP; update tableName=USER_GROUP_MEMBERSHIP; addNotNullConstraint columnName=MEMBERSHIP_TYPE, tableName=USER_GROUP_MEMBERSHIP		\N	4.29.1	\N	\N	2546741820
31296-persist-revoked-access-tokens	keycloak	META-INF/jpa-changelog-26.0.0.xml	2025-11-07 20:19:13.622966	142	EXECUTED	9:64ef94489d42a358e8304b0e245f0ed4	createTable tableName=REVOKED_TOKEN; addPrimaryKey constraintName=CONSTRAINT_RT, tableName=REVOKED_TOKEN		\N	4.29.1	\N	\N	2546741820
31725-index-persist-revoked-access-tokens	keycloak	META-INF/jpa-changelog-26.0.0.xml	2025-11-07 20:19:13.698442	143	EXECUTED	9:b994246ec2bf7c94da881e1d28782c7b	createIndex indexName=IDX_REV_TOKEN_ON_EXPIRE, tableName=REVOKED_TOKEN		\N	4.29.1	\N	\N	2546741820
26.0.0-idps-for-login	keycloak	META-INF/jpa-changelog-26.0.0.xml	2025-11-07 20:19:13.842484	144	EXECUTED	9:51f5fffadf986983d4bd59582c6c1604	addColumn tableName=IDENTITY_PROVIDER; createIndex indexName=IDX_IDP_REALM_ORG, tableName=IDENTITY_PROVIDER; createIndex indexName=IDX_IDP_FOR_LOGIN, tableName=IDENTITY_PROVIDER; customChange		\N	4.29.1	\N	\N	2546741820
26.0.0-32583-drop-redundant-index-on-client-session	keycloak	META-INF/jpa-changelog-26.0.0.xml	2025-11-07 20:19:13.897157	145	EXECUTED	9:24972d83bf27317a055d234187bb4af9	dropIndex indexName=IDX_US_SESS_ID_ON_CL_SESS, tableName=OFFLINE_CLIENT_SESSION		\N	4.29.1	\N	\N	2546741820
26.0.0.32582-remove-tables-user-session-user-session-note-and-client-session	keycloak	META-INF/jpa-changelog-26.0.0.xml	2025-11-07 20:19:13.93211	146	EXECUTED	9:febdc0f47f2ed241c59e60f58c3ceea5	dropTable tableName=CLIENT_SESSION_ROLE; dropTable tableName=CLIENT_SESSION_NOTE; dropTable tableName=CLIENT_SESSION_PROT_MAPPER; dropTable tableName=CLIENT_SESSION_AUTH_STATUS; dropTable tableName=CLIENT_USER_SESSION_NOTE; dropTable tableName=CLI...		\N	4.29.1	\N	\N	2546741820
26.0.0-33201-org-redirect-url	keycloak	META-INF/jpa-changelog-26.0.0.xml	2025-11-07 20:19:13.945855	147	EXECUTED	9:4d0e22b0ac68ebe9794fa9cb752ea660	addColumn tableName=ORG		\N	4.29.1	\N	\N	2546741820
26.0.6-34013	keycloak	META-INF/jpa-changelog-26.0.6.xml	2025-11-07 20:19:13.977004	148	EXECUTED	9:e6b686a15759aef99a6d758a5c4c6a26	addColumn tableName=ADMIN_EVENT_ENTITY		\N	4.29.1	\N	\N	2546741820
\.


--
-- Data for Name: databasechangeloglock; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.databasechangeloglock (id, locked, lockgranted, lockedby) FROM stdin;
1	f	\N	\N
1000	f	\N	\N
\.


--
-- Data for Name: default_client_scope; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.default_client_scope (realm_id, scope_id, default_scope) FROM stdin;
5be18a3e-7181-4862-867b-45aff91b9b87	461e2807-85fa-4147-b6cc-7c72852a2430	f
5be18a3e-7181-4862-867b-45aff91b9b87	8c914f2e-64ad-41b1-857f-8a8bf62ed0b1	t
5be18a3e-7181-4862-867b-45aff91b9b87	bf63aca5-a028-4427-afec-679fc54e78ba	t
5be18a3e-7181-4862-867b-45aff91b9b87	75cee988-908f-4f5c-9bcc-072208c81168	t
5be18a3e-7181-4862-867b-45aff91b9b87	9d4c6a24-8c01-4658-b3f5-da010d0a8f5f	t
5be18a3e-7181-4862-867b-45aff91b9b87	1038a83e-ad8a-4643-a4fd-07e2cde170f4	f
5be18a3e-7181-4862-867b-45aff91b9b87	95506dce-4939-4d6a-8700-95d1cedead31	f
5be18a3e-7181-4862-867b-45aff91b9b87	d8ef9497-8cf0-4560-824a-4c9329319677	t
5be18a3e-7181-4862-867b-45aff91b9b87	dc5d8147-1c9b-4dea-856e-6a701be77a28	t
5be18a3e-7181-4862-867b-45aff91b9b87	4027eeb6-c7ad-4116-904b-a2df4e36b9e8	f
5be18a3e-7181-4862-867b-45aff91b9b87	3f8efb2a-e473-45eb-be11-7440abc689ac	t
5be18a3e-7181-4862-867b-45aff91b9b87	7ae1f834-5642-46dd-8e8c-15e04b03855b	t
5be18a3e-7181-4862-867b-45aff91b9b87	ed5212a6-310a-4582-9c92-3610bf722f23	f
21dfe33f-5923-4bfd-bc04-cf200e747656	7ccd275b-86ef-43e6-b48e-bb0950ef2196	f
21dfe33f-5923-4bfd-bc04-cf200e747656	7af22446-a644-47ee-b4ff-50ae92fa75b5	t
21dfe33f-5923-4bfd-bc04-cf200e747656	4f907d9a-50f0-4f21-a8bc-abba39a00872	t
21dfe33f-5923-4bfd-bc04-cf200e747656	a4ed44cb-bcd9-4403-bdf6-ff361131c239	t
21dfe33f-5923-4bfd-bc04-cf200e747656	1b300f54-3ac9-44c4-ad0b-414957f47ebc	t
21dfe33f-5923-4bfd-bc04-cf200e747656	6bc2853a-a28e-44de-9036-0e505be14d79	f
21dfe33f-5923-4bfd-bc04-cf200e747656	b8041d7f-a6a0-4d56-aad4-33750056ee31	f
21dfe33f-5923-4bfd-bc04-cf200e747656	e47d3371-e4be-45f3-89aa-4b74f1f87832	t
21dfe33f-5923-4bfd-bc04-cf200e747656	70c49995-ea6d-498b-bba4-7b4a51b46fe9	t
21dfe33f-5923-4bfd-bc04-cf200e747656	cc0c3d1c-4e90-47aa-aae0-44f1dcf89a15	f
21dfe33f-5923-4bfd-bc04-cf200e747656	f3951ff7-42a3-4fd7-9219-c8aecfb52169	t
21dfe33f-5923-4bfd-bc04-cf200e747656	a8710cae-609f-4d07-b2e8-bf878bb356d3	t
21dfe33f-5923-4bfd-bc04-cf200e747656	92d3c51f-da77-4ec0-a58a-3cf9a81d8bd1	f
\.


--
-- Data for Name: event_entity; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.event_entity (id, client_id, details_json, error, ip_address, realm_id, session_id, event_time, type, user_id, details_json_long_value) FROM stdin;
\.


--
-- Data for Name: fed_user_attribute; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.fed_user_attribute (id, name, user_id, realm_id, storage_provider_id, value, long_value_hash, long_value_hash_lower_case, long_value) FROM stdin;
\.


--
-- Data for Name: fed_user_consent; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.fed_user_consent (id, client_id, user_id, realm_id, storage_provider_id, created_date, last_updated_date, client_storage_provider, external_client_id) FROM stdin;
\.


--
-- Data for Name: fed_user_consent_cl_scope; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.fed_user_consent_cl_scope (user_consent_id, scope_id) FROM stdin;
\.


--
-- Data for Name: fed_user_credential; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.fed_user_credential (id, salt, type, created_date, user_id, realm_id, storage_provider_id, user_label, secret_data, credential_data, priority) FROM stdin;
\.


--
-- Data for Name: fed_user_group_membership; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.fed_user_group_membership (group_id, user_id, realm_id, storage_provider_id) FROM stdin;
\.


--
-- Data for Name: fed_user_required_action; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.fed_user_required_action (required_action, user_id, realm_id, storage_provider_id) FROM stdin;
\.


--
-- Data for Name: fed_user_role_mapping; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.fed_user_role_mapping (role_id, user_id, realm_id, storage_provider_id) FROM stdin;
\.


--
-- Data for Name: federated_identity; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.federated_identity (identity_provider, realm_id, federated_user_id, federated_username, token, user_id) FROM stdin;
\.


--
-- Data for Name: federated_user; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.federated_user (id, storage_provider_id, realm_id) FROM stdin;
\.


--
-- Data for Name: group_attribute; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.group_attribute (id, name, value, group_id) FROM stdin;
\.


--
-- Data for Name: group_role_mapping; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.group_role_mapping (role_id, group_id) FROM stdin;
\.


--
-- Data for Name: identity_provider; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.identity_provider (internal_id, enabled, provider_alias, provider_id, store_token, authenticate_by_default, realm_id, add_token_role, trust_email, first_broker_login_flow_id, post_broker_login_flow_id, provider_display_name, link_only, organization_id, hide_on_login) FROM stdin;
\.


--
-- Data for Name: identity_provider_config; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.identity_provider_config (identity_provider_id, value, name) FROM stdin;
\.


--
-- Data for Name: identity_provider_mapper; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.identity_provider_mapper (id, name, idp_alias, idp_mapper_name, realm_id) FROM stdin;
\.


--
-- Data for Name: idp_mapper_config; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.idp_mapper_config (idp_mapper_id, value, name) FROM stdin;
\.


--
-- Data for Name: keycloak_group; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.keycloak_group (id, name, parent_group, realm_id, type) FROM stdin;
\.


--
-- Data for Name: keycloak_role; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.keycloak_role (id, client_realm_constraint, client_role, description, name, realm_id, client, realm) FROM stdin;
88007421-49af-4531-9b09-3025a88deb0f	5be18a3e-7181-4862-867b-45aff91b9b87	f	${role_default-roles}	default-roles-master	5be18a3e-7181-4862-867b-45aff91b9b87	\N	\N
4bd7b272-2bff-4959-ad20-f9438630c2a2	5be18a3e-7181-4862-867b-45aff91b9b87	f	${role_create-realm}	create-realm	5be18a3e-7181-4862-867b-45aff91b9b87	\N	\N
e7ecdf7c-50e6-4c10-b17f-8075d29c107c	5be18a3e-7181-4862-867b-45aff91b9b87	f	${role_admin}	admin	5be18a3e-7181-4862-867b-45aff91b9b87	\N	\N
52f5dcd2-5b12-49e4-bae9-b99e0b630422	58c02ea4-9114-4070-86ce-72fd450066cf	t	${role_create-client}	create-client	5be18a3e-7181-4862-867b-45aff91b9b87	58c02ea4-9114-4070-86ce-72fd450066cf	\N
5457fffa-b9fd-4b86-bcf1-f4a3009eb7c8	58c02ea4-9114-4070-86ce-72fd450066cf	t	${role_view-realm}	view-realm	5be18a3e-7181-4862-867b-45aff91b9b87	58c02ea4-9114-4070-86ce-72fd450066cf	\N
34954d6e-4e14-4c18-ae2c-08f9d2455f0d	58c02ea4-9114-4070-86ce-72fd450066cf	t	${role_view-users}	view-users	5be18a3e-7181-4862-867b-45aff91b9b87	58c02ea4-9114-4070-86ce-72fd450066cf	\N
c74a110d-d528-464c-8957-37070c1d0cae	58c02ea4-9114-4070-86ce-72fd450066cf	t	${role_view-clients}	view-clients	5be18a3e-7181-4862-867b-45aff91b9b87	58c02ea4-9114-4070-86ce-72fd450066cf	\N
7d7d85d6-1d1b-4210-b520-7b2cad173cd4	58c02ea4-9114-4070-86ce-72fd450066cf	t	${role_view-events}	view-events	5be18a3e-7181-4862-867b-45aff91b9b87	58c02ea4-9114-4070-86ce-72fd450066cf	\N
730f195b-7671-4a4f-8e6b-02da8d7d0931	58c02ea4-9114-4070-86ce-72fd450066cf	t	${role_view-identity-providers}	view-identity-providers	5be18a3e-7181-4862-867b-45aff91b9b87	58c02ea4-9114-4070-86ce-72fd450066cf	\N
66dba1f0-0546-4212-99f8-6748abcd92e0	58c02ea4-9114-4070-86ce-72fd450066cf	t	${role_view-authorization}	view-authorization	5be18a3e-7181-4862-867b-45aff91b9b87	58c02ea4-9114-4070-86ce-72fd450066cf	\N
d706ce26-1d31-4ec5-9613-9853bb7aeaae	58c02ea4-9114-4070-86ce-72fd450066cf	t	${role_manage-realm}	manage-realm	5be18a3e-7181-4862-867b-45aff91b9b87	58c02ea4-9114-4070-86ce-72fd450066cf	\N
92ee1845-7384-4a41-abb8-957cf6dedb5b	58c02ea4-9114-4070-86ce-72fd450066cf	t	${role_manage-users}	manage-users	5be18a3e-7181-4862-867b-45aff91b9b87	58c02ea4-9114-4070-86ce-72fd450066cf	\N
d8fcc45c-ac4f-4dfc-b0d7-87b5fcfab5e6	58c02ea4-9114-4070-86ce-72fd450066cf	t	${role_manage-clients}	manage-clients	5be18a3e-7181-4862-867b-45aff91b9b87	58c02ea4-9114-4070-86ce-72fd450066cf	\N
f9e6b7fd-ca54-41b3-af13-c25c6edbcf3f	58c02ea4-9114-4070-86ce-72fd450066cf	t	${role_manage-events}	manage-events	5be18a3e-7181-4862-867b-45aff91b9b87	58c02ea4-9114-4070-86ce-72fd450066cf	\N
d2276970-2146-43da-972a-11a1a8e9e2a9	58c02ea4-9114-4070-86ce-72fd450066cf	t	${role_manage-identity-providers}	manage-identity-providers	5be18a3e-7181-4862-867b-45aff91b9b87	58c02ea4-9114-4070-86ce-72fd450066cf	\N
d8eb9aa1-8b4a-4c1e-9b8f-73d3b07780b4	58c02ea4-9114-4070-86ce-72fd450066cf	t	${role_manage-authorization}	manage-authorization	5be18a3e-7181-4862-867b-45aff91b9b87	58c02ea4-9114-4070-86ce-72fd450066cf	\N
d33628b0-7a53-4be2-9c1b-c3723cfc6f2b	58c02ea4-9114-4070-86ce-72fd450066cf	t	${role_query-users}	query-users	5be18a3e-7181-4862-867b-45aff91b9b87	58c02ea4-9114-4070-86ce-72fd450066cf	\N
656b2728-ed10-4826-9a50-31a4e259cd87	58c02ea4-9114-4070-86ce-72fd450066cf	t	${role_query-clients}	query-clients	5be18a3e-7181-4862-867b-45aff91b9b87	58c02ea4-9114-4070-86ce-72fd450066cf	\N
ca02fd4e-9a60-4bf5-809e-c1a0431a0d23	58c02ea4-9114-4070-86ce-72fd450066cf	t	${role_query-realms}	query-realms	5be18a3e-7181-4862-867b-45aff91b9b87	58c02ea4-9114-4070-86ce-72fd450066cf	\N
e180f3e9-0bc3-482f-9e53-8ba7ac88a09a	58c02ea4-9114-4070-86ce-72fd450066cf	t	${role_query-groups}	query-groups	5be18a3e-7181-4862-867b-45aff91b9b87	58c02ea4-9114-4070-86ce-72fd450066cf	\N
77df31c7-b5c4-4835-ae49-cfe0ed6a8f1e	d0dc1596-18e2-4ccc-bd5e-cc8a1b52db61	t	${role_view-profile}	view-profile	5be18a3e-7181-4862-867b-45aff91b9b87	d0dc1596-18e2-4ccc-bd5e-cc8a1b52db61	\N
79d032d2-4b1f-4b01-9418-fa6ad7e29efd	d0dc1596-18e2-4ccc-bd5e-cc8a1b52db61	t	${role_manage-account}	manage-account	5be18a3e-7181-4862-867b-45aff91b9b87	d0dc1596-18e2-4ccc-bd5e-cc8a1b52db61	\N
38cfe765-0c0a-457e-a516-f72985e8169b	d0dc1596-18e2-4ccc-bd5e-cc8a1b52db61	t	${role_manage-account-links}	manage-account-links	5be18a3e-7181-4862-867b-45aff91b9b87	d0dc1596-18e2-4ccc-bd5e-cc8a1b52db61	\N
e76abca2-a556-44e8-9515-162a0c1d0730	d0dc1596-18e2-4ccc-bd5e-cc8a1b52db61	t	${role_view-applications}	view-applications	5be18a3e-7181-4862-867b-45aff91b9b87	d0dc1596-18e2-4ccc-bd5e-cc8a1b52db61	\N
34778562-adf1-404c-98e5-dcb5cc9da021	d0dc1596-18e2-4ccc-bd5e-cc8a1b52db61	t	${role_view-consent}	view-consent	5be18a3e-7181-4862-867b-45aff91b9b87	d0dc1596-18e2-4ccc-bd5e-cc8a1b52db61	\N
0e67c975-30bf-44be-9a8f-f62403b9baee	d0dc1596-18e2-4ccc-bd5e-cc8a1b52db61	t	${role_manage-consent}	manage-consent	5be18a3e-7181-4862-867b-45aff91b9b87	d0dc1596-18e2-4ccc-bd5e-cc8a1b52db61	\N
32ab400c-b0bc-4231-b184-a9c7ea819c8c	d0dc1596-18e2-4ccc-bd5e-cc8a1b52db61	t	${role_view-groups}	view-groups	5be18a3e-7181-4862-867b-45aff91b9b87	d0dc1596-18e2-4ccc-bd5e-cc8a1b52db61	\N
ecc51445-b003-4562-b4d1-a9f76d42fe3d	d0dc1596-18e2-4ccc-bd5e-cc8a1b52db61	t	${role_delete-account}	delete-account	5be18a3e-7181-4862-867b-45aff91b9b87	d0dc1596-18e2-4ccc-bd5e-cc8a1b52db61	\N
afa583ad-4d2c-4203-8c15-708ec4a1690f	89738f4a-9efa-482e-8c1e-3a5b2a1ac2a6	t	${role_read-token}	read-token	5be18a3e-7181-4862-867b-45aff91b9b87	89738f4a-9efa-482e-8c1e-3a5b2a1ac2a6	\N
b9040c2a-3367-4272-968d-d6c5f4ed6623	58c02ea4-9114-4070-86ce-72fd450066cf	t	${role_impersonation}	impersonation	5be18a3e-7181-4862-867b-45aff91b9b87	58c02ea4-9114-4070-86ce-72fd450066cf	\N
e23e71ce-b6c5-4aa7-9077-bf1cb8878745	5be18a3e-7181-4862-867b-45aff91b9b87	f	${role_offline-access}	offline_access	5be18a3e-7181-4862-867b-45aff91b9b87	\N	\N
2a4954f4-f206-4ce4-b19f-b744d2d5ea44	5be18a3e-7181-4862-867b-45aff91b9b87	f	${role_uma_authorization}	uma_authorization	5be18a3e-7181-4862-867b-45aff91b9b87	\N	\N
0a8a743d-b0e0-4d1e-8747-7513a1e564d1	21dfe33f-5923-4bfd-bc04-cf200e747656	f	${role_default-roles}	default-roles-local	21dfe33f-5923-4bfd-bc04-cf200e747656	\N	\N
e3537e6b-8379-467f-bfe8-15cdc4a32f52	a21e795c-3dc5-4e25-9faf-13c6c3df2b02	t	${role_create-client}	create-client	5be18a3e-7181-4862-867b-45aff91b9b87	a21e795c-3dc5-4e25-9faf-13c6c3df2b02	\N
f1007e04-3356-41b5-9d6f-7043f7c2c701	a21e795c-3dc5-4e25-9faf-13c6c3df2b02	t	${role_view-realm}	view-realm	5be18a3e-7181-4862-867b-45aff91b9b87	a21e795c-3dc5-4e25-9faf-13c6c3df2b02	\N
022693bc-6df4-4889-895e-e904c52bd3a2	a21e795c-3dc5-4e25-9faf-13c6c3df2b02	t	${role_view-users}	view-users	5be18a3e-7181-4862-867b-45aff91b9b87	a21e795c-3dc5-4e25-9faf-13c6c3df2b02	\N
6cf31d65-54a3-432e-874e-cd9fc49c6642	a21e795c-3dc5-4e25-9faf-13c6c3df2b02	t	${role_view-clients}	view-clients	5be18a3e-7181-4862-867b-45aff91b9b87	a21e795c-3dc5-4e25-9faf-13c6c3df2b02	\N
44258421-f818-4834-b96e-2eb0fc51f36d	a21e795c-3dc5-4e25-9faf-13c6c3df2b02	t	${role_view-events}	view-events	5be18a3e-7181-4862-867b-45aff91b9b87	a21e795c-3dc5-4e25-9faf-13c6c3df2b02	\N
3901f48f-bd83-433e-affc-45db7f50e220	a21e795c-3dc5-4e25-9faf-13c6c3df2b02	t	${role_view-identity-providers}	view-identity-providers	5be18a3e-7181-4862-867b-45aff91b9b87	a21e795c-3dc5-4e25-9faf-13c6c3df2b02	\N
b02d5067-0e48-438b-9b57-14f323515384	a21e795c-3dc5-4e25-9faf-13c6c3df2b02	t	${role_view-authorization}	view-authorization	5be18a3e-7181-4862-867b-45aff91b9b87	a21e795c-3dc5-4e25-9faf-13c6c3df2b02	\N
86c01e31-5dd9-484c-ace5-8b7690f7e416	a21e795c-3dc5-4e25-9faf-13c6c3df2b02	t	${role_manage-realm}	manage-realm	5be18a3e-7181-4862-867b-45aff91b9b87	a21e795c-3dc5-4e25-9faf-13c6c3df2b02	\N
322035e2-a62a-4931-a600-d0170fbf6df7	a21e795c-3dc5-4e25-9faf-13c6c3df2b02	t	${role_manage-users}	manage-users	5be18a3e-7181-4862-867b-45aff91b9b87	a21e795c-3dc5-4e25-9faf-13c6c3df2b02	\N
a1f76f7e-31e1-4c60-bebc-31ad66d25983	a21e795c-3dc5-4e25-9faf-13c6c3df2b02	t	${role_manage-clients}	manage-clients	5be18a3e-7181-4862-867b-45aff91b9b87	a21e795c-3dc5-4e25-9faf-13c6c3df2b02	\N
5923bcb5-4829-43a5-9171-0a59eb980095	a21e795c-3dc5-4e25-9faf-13c6c3df2b02	t	${role_manage-events}	manage-events	5be18a3e-7181-4862-867b-45aff91b9b87	a21e795c-3dc5-4e25-9faf-13c6c3df2b02	\N
c94843e6-4cfd-4a4d-890c-d6343a90ffb7	a21e795c-3dc5-4e25-9faf-13c6c3df2b02	t	${role_manage-identity-providers}	manage-identity-providers	5be18a3e-7181-4862-867b-45aff91b9b87	a21e795c-3dc5-4e25-9faf-13c6c3df2b02	\N
fc9d6a3e-64b2-4b6d-946e-3ca669750b05	a21e795c-3dc5-4e25-9faf-13c6c3df2b02	t	${role_manage-authorization}	manage-authorization	5be18a3e-7181-4862-867b-45aff91b9b87	a21e795c-3dc5-4e25-9faf-13c6c3df2b02	\N
dbba3239-df15-4dc7-804c-638b80862e85	a21e795c-3dc5-4e25-9faf-13c6c3df2b02	t	${role_query-users}	query-users	5be18a3e-7181-4862-867b-45aff91b9b87	a21e795c-3dc5-4e25-9faf-13c6c3df2b02	\N
859cd9c7-3246-47db-94c8-7dbb36bd4361	a21e795c-3dc5-4e25-9faf-13c6c3df2b02	t	${role_query-clients}	query-clients	5be18a3e-7181-4862-867b-45aff91b9b87	a21e795c-3dc5-4e25-9faf-13c6c3df2b02	\N
c5c23393-73b2-4a00-a8da-e1ceed33fcc8	a21e795c-3dc5-4e25-9faf-13c6c3df2b02	t	${role_query-realms}	query-realms	5be18a3e-7181-4862-867b-45aff91b9b87	a21e795c-3dc5-4e25-9faf-13c6c3df2b02	\N
dae29efa-69ba-4e6c-8793-cadfd2824e3f	a21e795c-3dc5-4e25-9faf-13c6c3df2b02	t	${role_query-groups}	query-groups	5be18a3e-7181-4862-867b-45aff91b9b87	a21e795c-3dc5-4e25-9faf-13c6c3df2b02	\N
00d3f0d7-d0a6-46a6-a328-577f85af26b4	fc2f4568-b7af-409b-9647-d1632a32abf7	t	${role_realm-admin}	realm-admin	21dfe33f-5923-4bfd-bc04-cf200e747656	fc2f4568-b7af-409b-9647-d1632a32abf7	\N
150e4aa0-1449-4dca-a879-ba26b20dadfe	fc2f4568-b7af-409b-9647-d1632a32abf7	t	${role_create-client}	create-client	21dfe33f-5923-4bfd-bc04-cf200e747656	fc2f4568-b7af-409b-9647-d1632a32abf7	\N
cc386f4e-f506-403e-b285-95cd0fa0d867	fc2f4568-b7af-409b-9647-d1632a32abf7	t	${role_view-realm}	view-realm	21dfe33f-5923-4bfd-bc04-cf200e747656	fc2f4568-b7af-409b-9647-d1632a32abf7	\N
7b858e3a-ae86-427a-a84a-8f9deaf6501d	fc2f4568-b7af-409b-9647-d1632a32abf7	t	${role_view-users}	view-users	21dfe33f-5923-4bfd-bc04-cf200e747656	fc2f4568-b7af-409b-9647-d1632a32abf7	\N
e542a3c9-c10c-4abc-a38b-079bd23afee2	fc2f4568-b7af-409b-9647-d1632a32abf7	t	${role_view-clients}	view-clients	21dfe33f-5923-4bfd-bc04-cf200e747656	fc2f4568-b7af-409b-9647-d1632a32abf7	\N
ede5fd63-28d0-479c-924b-1e32391f8648	fc2f4568-b7af-409b-9647-d1632a32abf7	t	${role_view-events}	view-events	21dfe33f-5923-4bfd-bc04-cf200e747656	fc2f4568-b7af-409b-9647-d1632a32abf7	\N
638475f1-e7f1-45ee-8dff-20606259e993	fc2f4568-b7af-409b-9647-d1632a32abf7	t	${role_view-identity-providers}	view-identity-providers	21dfe33f-5923-4bfd-bc04-cf200e747656	fc2f4568-b7af-409b-9647-d1632a32abf7	\N
b5e10000-5cc3-4f0c-9894-e13bc0b61bf7	fc2f4568-b7af-409b-9647-d1632a32abf7	t	${role_view-authorization}	view-authorization	21dfe33f-5923-4bfd-bc04-cf200e747656	fc2f4568-b7af-409b-9647-d1632a32abf7	\N
461d3a94-99f9-425b-89d8-9fa2bec03ab7	fc2f4568-b7af-409b-9647-d1632a32abf7	t	${role_manage-realm}	manage-realm	21dfe33f-5923-4bfd-bc04-cf200e747656	fc2f4568-b7af-409b-9647-d1632a32abf7	\N
7db617b0-8dff-40d9-a47b-cc7b092fe9e5	fc2f4568-b7af-409b-9647-d1632a32abf7	t	${role_manage-users}	manage-users	21dfe33f-5923-4bfd-bc04-cf200e747656	fc2f4568-b7af-409b-9647-d1632a32abf7	\N
de27b490-ec70-4c3e-9c6c-c45d6e7d73a4	fc2f4568-b7af-409b-9647-d1632a32abf7	t	${role_manage-clients}	manage-clients	21dfe33f-5923-4bfd-bc04-cf200e747656	fc2f4568-b7af-409b-9647-d1632a32abf7	\N
6ee08807-aa8d-402c-a0cc-d6c7f920d930	fc2f4568-b7af-409b-9647-d1632a32abf7	t	${role_manage-events}	manage-events	21dfe33f-5923-4bfd-bc04-cf200e747656	fc2f4568-b7af-409b-9647-d1632a32abf7	\N
539a1ff1-d18c-4d67-ac93-fbe774d11be9	fc2f4568-b7af-409b-9647-d1632a32abf7	t	${role_manage-identity-providers}	manage-identity-providers	21dfe33f-5923-4bfd-bc04-cf200e747656	fc2f4568-b7af-409b-9647-d1632a32abf7	\N
1f25af04-e298-46ae-9570-273328c82de8	fc2f4568-b7af-409b-9647-d1632a32abf7	t	${role_manage-authorization}	manage-authorization	21dfe33f-5923-4bfd-bc04-cf200e747656	fc2f4568-b7af-409b-9647-d1632a32abf7	\N
62c510c3-abf2-418b-8a12-f8ea21199f05	fc2f4568-b7af-409b-9647-d1632a32abf7	t	${role_query-users}	query-users	21dfe33f-5923-4bfd-bc04-cf200e747656	fc2f4568-b7af-409b-9647-d1632a32abf7	\N
99f49fc8-c08e-4c20-b20f-c3626592aad6	fc2f4568-b7af-409b-9647-d1632a32abf7	t	${role_query-clients}	query-clients	21dfe33f-5923-4bfd-bc04-cf200e747656	fc2f4568-b7af-409b-9647-d1632a32abf7	\N
6095ffc1-62ed-4169-b614-7d0b166a99db	fc2f4568-b7af-409b-9647-d1632a32abf7	t	${role_query-realms}	query-realms	21dfe33f-5923-4bfd-bc04-cf200e747656	fc2f4568-b7af-409b-9647-d1632a32abf7	\N
8acb6c84-2b3c-470c-a003-0a6f0f2b48f1	fc2f4568-b7af-409b-9647-d1632a32abf7	t	${role_query-groups}	query-groups	21dfe33f-5923-4bfd-bc04-cf200e747656	fc2f4568-b7af-409b-9647-d1632a32abf7	\N
9164548b-a33a-434d-ab72-fabd8d248706	e1fd0113-c702-4617-9068-7c9142d6b48b	t	${role_view-profile}	view-profile	21dfe33f-5923-4bfd-bc04-cf200e747656	e1fd0113-c702-4617-9068-7c9142d6b48b	\N
c2a86f85-7cc1-4205-b98a-42b8557945e1	e1fd0113-c702-4617-9068-7c9142d6b48b	t	${role_manage-account}	manage-account	21dfe33f-5923-4bfd-bc04-cf200e747656	e1fd0113-c702-4617-9068-7c9142d6b48b	\N
26bb3b89-c68d-4c8e-aeaa-a98f91087c9f	e1fd0113-c702-4617-9068-7c9142d6b48b	t	${role_manage-account-links}	manage-account-links	21dfe33f-5923-4bfd-bc04-cf200e747656	e1fd0113-c702-4617-9068-7c9142d6b48b	\N
96651dad-b25f-4ba3-994f-349b393cee0c	e1fd0113-c702-4617-9068-7c9142d6b48b	t	${role_view-applications}	view-applications	21dfe33f-5923-4bfd-bc04-cf200e747656	e1fd0113-c702-4617-9068-7c9142d6b48b	\N
40c60837-b911-4bc0-aea5-26a9852c207c	e1fd0113-c702-4617-9068-7c9142d6b48b	t	${role_view-consent}	view-consent	21dfe33f-5923-4bfd-bc04-cf200e747656	e1fd0113-c702-4617-9068-7c9142d6b48b	\N
ef743bff-0eee-40ef-ab63-8eac0cc21101	e1fd0113-c702-4617-9068-7c9142d6b48b	t	${role_manage-consent}	manage-consent	21dfe33f-5923-4bfd-bc04-cf200e747656	e1fd0113-c702-4617-9068-7c9142d6b48b	\N
58eca8a2-317c-4212-9cbc-e089f3cfb715	e1fd0113-c702-4617-9068-7c9142d6b48b	t	${role_view-groups}	view-groups	21dfe33f-5923-4bfd-bc04-cf200e747656	e1fd0113-c702-4617-9068-7c9142d6b48b	\N
07997bc0-1dbc-492b-aab4-e9b569e5d7ce	e1fd0113-c702-4617-9068-7c9142d6b48b	t	${role_delete-account}	delete-account	21dfe33f-5923-4bfd-bc04-cf200e747656	e1fd0113-c702-4617-9068-7c9142d6b48b	\N
4f9f1fd9-8af5-48d5-b275-5974bcddd8f6	a21e795c-3dc5-4e25-9faf-13c6c3df2b02	t	${role_impersonation}	impersonation	5be18a3e-7181-4862-867b-45aff91b9b87	a21e795c-3dc5-4e25-9faf-13c6c3df2b02	\N
42e83457-164e-4ee2-a679-58886b5f3357	fc2f4568-b7af-409b-9647-d1632a32abf7	t	${role_impersonation}	impersonation	21dfe33f-5923-4bfd-bc04-cf200e747656	fc2f4568-b7af-409b-9647-d1632a32abf7	\N
7312e1cf-4404-450c-9747-15d0ca5f221b	23ea499c-7892-4f61-9cd3-9fbe4c9f493c	t	${role_read-token}	read-token	21dfe33f-5923-4bfd-bc04-cf200e747656	23ea499c-7892-4f61-9cd3-9fbe4c9f493c	\N
cc0dc39f-c6fd-4e0d-81bb-e9ea0bcd1ed6	21dfe33f-5923-4bfd-bc04-cf200e747656	f	${role_offline-access}	offline_access	21dfe33f-5923-4bfd-bc04-cf200e747656	\N	\N
5f7c14f8-1f1f-4742-9640-6834529d865d	21dfe33f-5923-4bfd-bc04-cf200e747656	f	${role_uma_authorization}	uma_authorization	21dfe33f-5923-4bfd-bc04-cf200e747656	\N	\N
70f6f49a-2ad3-43ed-a6f1-8687b61f5b66	21dfe33f-5923-4bfd-bc04-cf200e747656	f		ROLE_USER	21dfe33f-5923-4bfd-bc04-cf200e747656	\N	\N
5db3f6d8-31ea-4ea8-af29-e8e2f244bf73	40f8f713-e1c4-4e9d-a804-2ec22fb3d118	t	\N	uma_protection	5be18a3e-7181-4862-867b-45aff91b9b87	40f8f713-e1c4-4e9d-a804-2ec22fb3d118	\N
7581451c-4ff2-4d0a-8402-14d22578ba17	ab4df486-dff6-488a-aa26-56cccddaf5fc	t	\N	uma_protection	21dfe33f-5923-4bfd-bc04-cf200e747656	ab4df486-dff6-488a-aa26-56cccddaf5fc	\N
\.


--
-- Data for Name: migration_model; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.migration_model (id, version, update_time) FROM stdin;
0ikme	26.0.8	1762546754
\.


--
-- Data for Name: offline_client_session; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.offline_client_session (user_session_id, client_id, offline_flag, "timestamp", data, client_storage_provider, external_client_id, version) FROM stdin;
9c2d8206-0a9f-4034-ab1b-b4dd93074681	489d25cc-3b6e-49bc-b4d3-7ece35cf3eff	0	1762554610	{"authMethod":"openid-connect","redirectUri":"https://keycloak.test:9443/admin/master/console/","notes":{"clientId":"489d25cc-3b6e-49bc-b4d3-7ece35cf3eff","iss":"https://keycloak.test:9443/realms/master","startedAt":"1762554489","response_type":"code","level-of-authentication":"-1","code_challenge_method":"S256","nonce":"2c1d3abd-aa22-4b47-960c-bd856635c4e0","response_mode":"query","scope":"openid","userSessionStartedAt":"1762554489","redirect_uri":"https://keycloak.test:9443/admin/master/console/","state":"11d8b961-e929-4f3e-aa56-493eeb28e4ec","code_challenge":"luYrJkOiM0mdjq0oS4JSyKwRNzueHj1cpaHSd0uzMHE"}}	local	local	1
4d1be7b5-2617-4041-ad9f-532f8c2f20c3	9f5333a7-931d-4663-b07d-c89928cd6498	0	1762554370	{"authMethod":"openid-connect","redirectUri":"https://keycloak.test:9443/realms/local/account","notes":{"clientId":"9f5333a7-931d-4663-b07d-c89928cd6498","iss":"https://keycloak.test:9443/realms/local","startedAt":"1762554370","response_type":"code","level-of-authentication":"-1","code_challenge_method":"S256","nonce":"c0977c24-5159-49cb-a424-41d4f0f99dbb","response_mode":"query","scope":"openid","userSessionStartedAt":"1762554370","redirect_uri":"https://keycloak.test:9443/realms/local/account","state":"248cddda-7d3b-4c3c-b58a-2e86adb87f8f","code_challenge":"J19oMdsdSy7dsI485IxddjgJH09cwH-51sCPRHDah6g"}}	local	local	0
e7f0fb15-5f58-4a76-a989-0e5f36ff693b	489d25cc-3b6e-49bc-b4d3-7ece35cf3eff	0	1762558444	{"authMethod":"openid-connect","redirectUri":"https://keycloak.test:9443/admin/master/console/#/local/clients","notes":{"clientId":"489d25cc-3b6e-49bc-b4d3-7ece35cf3eff","iss":"https://keycloak.test:9443/realms/master","startedAt":"1762558378","response_type":"code","level-of-authentication":"-1","code_challenge_method":"S256","nonce":"58835595-bc3b-4ce4-aece-47461e2f8dde","response_mode":"query","scope":"openid","userSessionStartedAt":"1762558378","redirect_uri":"https://keycloak.test:9443/admin/master/console/#/local/clients","state":"0ac1ee45-70d5-4f10-a3d1-e8e68fea0509","code_challenge":"Br8MBUj2gjaV-7hu7j0QprgVq2AIkWAxswNRV-WR80E"}}	local	local	2
8c0bb52a-8d3f-42f5-9026-e62253cbcdf4	ab4df486-dff6-488a-aa26-56cccddaf5fc	0	1762558458	{"authMethod":"openid-connect","notes":{"clientId":"ab4df486-dff6-488a-aa26-56cccddaf5fc","scope":"openid profile email","userSessionStartedAt":"1762558458","iss":"https://keycloak.test:9443/realms/local","startedAt":"1762558458","level-of-authentication":"-1"}}	local	local	0
\.


--
-- Data for Name: offline_user_session; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.offline_user_session (user_session_id, user_id, realm_id, created_on, offline_flag, data, last_session_refresh, broker_session_id, version) FROM stdin;
4d1be7b5-2617-4041-ad9f-532f8c2f20c3	dde646db-f964-4728-9ce9-e9552001b16a	21dfe33f-5923-4bfd-bc04-cf200e747656	1762554370	0	{"ipAddress":"172.17.0.1","authMethod":"openid-connect","rememberMe":false,"started":0,"notes":{"KC_DEVICE_NOTE":"eyJpcEFkZHJlc3MiOiIxNzIuMTcuMC4xIiwib3MiOiJXaW5kb3dzIiwib3NWZXJzaW9uIjoiMTAiLCJicm93c2VyIjoiQ2hyb21lLzE0MS4wLjAiLCJkZXZpY2UiOiJPdGhlciIsImxhc3RBY2Nlc3MiOjAsIm1vYmlsZSI6ZmFsc2V9","AUTH_TIME":"1762554370","authenticators-completed":"{\\"f3d6f551-e7ea-4f7e-924f-da55c56e1d9a\\":1762554370}"},"state":"LOGGED_IN"}	1762554371	\N	1
9c2d8206-0a9f-4034-ab1b-b4dd93074681	c3557eb9-249e-4dd9-b72d-9d2977b1af9d	5be18a3e-7181-4862-867b-45aff91b9b87	1762554489	0	{"ipAddress":"172.17.0.1","authMethod":"openid-connect","rememberMe":false,"started":0,"notes":{"KC_DEVICE_NOTE":"eyJpcEFkZHJlc3MiOiIxNzIuMTcuMC4xIiwib3MiOiJXaW5kb3dzIiwib3NWZXJzaW9uIjoiMTAiLCJicm93c2VyIjoiQ2hyb21lLzE0MS4wLjAiLCJkZXZpY2UiOiJPdGhlciIsImxhc3RBY2Nlc3MiOjAsIm1vYmlsZSI6ZmFsc2V9","AUTH_TIME":"1762554489","authenticators-completed":"{\\"b97aaa37-a74c-4b5d-bd85-c23a439e382c\\":1762554489}"},"state":"LOGGED_IN"}	1762554610	\N	1
e7f0fb15-5f58-4a76-a989-0e5f36ff693b	c3557eb9-249e-4dd9-b72d-9d2977b1af9d	5be18a3e-7181-4862-867b-45aff91b9b87	1762558378	0	{"ipAddress":"172.19.0.1","authMethod":"openid-connect","rememberMe":false,"started":0,"notes":{"KC_DEVICE_NOTE":"eyJpcEFkZHJlc3MiOiIxNzIuMTkuMC4xIiwib3MiOiJXaW5kb3dzIiwib3NWZXJzaW9uIjoiMTAiLCJicm93c2VyIjoiQ2hyb21lLzE0MS4wLjAiLCJkZXZpY2UiOiJPdGhlciIsImxhc3RBY2Nlc3MiOjAsIm1vYmlsZSI6ZmFsc2V9","AUTH_TIME":"1762558378","authenticators-completed":"{\\"b97aaa37-a74c-4b5d-bd85-c23a439e382c\\":1762558378}"},"state":"LOGGED_IN"}	1762558444	\N	2
8c0bb52a-8d3f-42f5-9026-e62253cbcdf4	dde646db-f964-4728-9ce9-e9552001b16a	21dfe33f-5923-4bfd-bc04-cf200e747656	1762558458	0	{"ipAddress":"172.19.0.1","authMethod":"openid-connect","rememberMe":false,"started":0,"notes":{"KC_DEVICE_NOTE":"eyJpcEFkZHJlc3MiOiIxNzIuMTkuMC4xIiwib3MiOiJPdGhlciIsIm9zVmVyc2lvbiI6IlVua25vd24iLCJicm93c2VyIjoiUG9zdG1hblJ1bnRpbWUvNy40OS4xIiwiZGV2aWNlIjoiT3RoZXIiLCJsYXN0QWNjZXNzIjowLCJtb2JpbGUiOmZhbHNlfQ==","authenticators-completed":"{\\"89ca3635-a445-496d-b709-929e95c93511\\":1762558458,\\"9153b489-9b6d-468b-b25f-44e14090d8dd\\":1762558458}"},"state":"LOGGED_IN"}	1762558458	\N	0
\.


--
-- Data for Name: org; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.org (id, enabled, realm_id, group_id, name, description, alias, redirect_url) FROM stdin;
\.


--
-- Data for Name: org_domain; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.org_domain (id, name, verified, org_id) FROM stdin;
\.


--
-- Data for Name: policy_config; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.policy_config (policy_id, name, value) FROM stdin;
2954b2a2-7a31-4064-918e-6cb0d75cf43a	code	// by default, grants any permission associated with this policy\n$evaluation.grant();\n
2c907709-c0fa-48bf-bf7a-3e0900464a00	defaultResourceType	urn:local-client:resources:default
385360f0-fe21-476f-aa17-6364f7ee537e	code	// by default, grants any permission associated with this policy\n$evaluation.grant();\n
f2a0b9fb-9f81-408d-9d85-5179936edbb4	defaultResourceType	urn:local-client:resources:default
\.


--
-- Data for Name: protocol_mapper; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.protocol_mapper (id, name, protocol, protocol_mapper_name, client_id, client_scope_id) FROM stdin;
6185053c-ef47-483f-9aff-3979f7cd5d68	audience resolve	openid-connect	oidc-audience-resolve-mapper	250d1167-7f36-432a-96eb-492124c372b1	\N
6c48de52-8a8f-4617-b95f-23e48cd446d8	locale	openid-connect	oidc-usermodel-attribute-mapper	489d25cc-3b6e-49bc-b4d3-7ece35cf3eff	\N
d0e8d539-7524-4c6f-8cc5-ed57de473bac	role list	saml	saml-role-list-mapper	\N	8c914f2e-64ad-41b1-857f-8a8bf62ed0b1
82e2d231-012d-4be5-938d-b8afb582a617	organization	saml	saml-organization-membership-mapper	\N	bf63aca5-a028-4427-afec-679fc54e78ba
240109d7-f1ed-4e7d-835f-4bb363cf65ec	full name	openid-connect	oidc-full-name-mapper	\N	75cee988-908f-4f5c-9bcc-072208c81168
c1297fa4-d1fb-4ea4-962d-10458656c763	family name	openid-connect	oidc-usermodel-attribute-mapper	\N	75cee988-908f-4f5c-9bcc-072208c81168
3c3a1307-2400-4ef1-86f3-6b9214bc5eba	given name	openid-connect	oidc-usermodel-attribute-mapper	\N	75cee988-908f-4f5c-9bcc-072208c81168
f457a039-5bfe-4d4c-a693-a682e36597ab	middle name	openid-connect	oidc-usermodel-attribute-mapper	\N	75cee988-908f-4f5c-9bcc-072208c81168
c1064f0e-24d2-4afb-8479-2ea2dac85169	nickname	openid-connect	oidc-usermodel-attribute-mapper	\N	75cee988-908f-4f5c-9bcc-072208c81168
33bb7496-5329-4f7c-94ca-37c11cb19b15	username	openid-connect	oidc-usermodel-attribute-mapper	\N	75cee988-908f-4f5c-9bcc-072208c81168
2d203ee8-69b6-47bd-8c67-8c5430f06c54	profile	openid-connect	oidc-usermodel-attribute-mapper	\N	75cee988-908f-4f5c-9bcc-072208c81168
3fc4ba98-8c1f-48df-a677-b7c80224173a	picture	openid-connect	oidc-usermodel-attribute-mapper	\N	75cee988-908f-4f5c-9bcc-072208c81168
07dff9f4-25ad-42c4-ac71-e2f463ce37a2	website	openid-connect	oidc-usermodel-attribute-mapper	\N	75cee988-908f-4f5c-9bcc-072208c81168
de18d987-457b-4cce-8d7b-efba1c91e738	gender	openid-connect	oidc-usermodel-attribute-mapper	\N	75cee988-908f-4f5c-9bcc-072208c81168
61eeb4b5-e07e-44de-b090-64577cca0ebb	birthdate	openid-connect	oidc-usermodel-attribute-mapper	\N	75cee988-908f-4f5c-9bcc-072208c81168
7b9892d6-e7b9-4454-95ff-542ccd6bfde4	zoneinfo	openid-connect	oidc-usermodel-attribute-mapper	\N	75cee988-908f-4f5c-9bcc-072208c81168
cedc997d-bbb2-490a-90df-61705ca423dd	locale	openid-connect	oidc-usermodel-attribute-mapper	\N	75cee988-908f-4f5c-9bcc-072208c81168
aa6aefde-f0a8-49f9-a9a7-8ffc081932c0	updated at	openid-connect	oidc-usermodel-attribute-mapper	\N	75cee988-908f-4f5c-9bcc-072208c81168
6e9c10d6-f745-478f-9e5f-5c873fbb6562	email	openid-connect	oidc-usermodel-attribute-mapper	\N	9d4c6a24-8c01-4658-b3f5-da010d0a8f5f
86dec864-8243-4c80-86d8-eee4a50faca8	email verified	openid-connect	oidc-usermodel-property-mapper	\N	9d4c6a24-8c01-4658-b3f5-da010d0a8f5f
9952b570-5458-4092-b0b4-90b7735df12f	address	openid-connect	oidc-address-mapper	\N	1038a83e-ad8a-4643-a4fd-07e2cde170f4
5ad6c02e-1820-4ddf-9ad7-cd464176aacb	phone number	openid-connect	oidc-usermodel-attribute-mapper	\N	95506dce-4939-4d6a-8700-95d1cedead31
53e44793-7974-4b15-9b24-248ebeb0f68b	phone number verified	openid-connect	oidc-usermodel-attribute-mapper	\N	95506dce-4939-4d6a-8700-95d1cedead31
a4fb0211-2cbd-40b5-b191-a4800d5357b6	realm roles	openid-connect	oidc-usermodel-realm-role-mapper	\N	d8ef9497-8cf0-4560-824a-4c9329319677
9f367bce-6f39-46e6-a1ce-92cd1cf9a27f	client roles	openid-connect	oidc-usermodel-client-role-mapper	\N	d8ef9497-8cf0-4560-824a-4c9329319677
b3852362-2ff1-4463-b328-22bcb81358f7	audience resolve	openid-connect	oidc-audience-resolve-mapper	\N	d8ef9497-8cf0-4560-824a-4c9329319677
6408bc89-5a42-4cca-a71d-00f3609decdc	allowed web origins	openid-connect	oidc-allowed-origins-mapper	\N	dc5d8147-1c9b-4dea-856e-6a701be77a28
c5a0fe7b-eb5a-4e40-82dc-71eaaeaee014	upn	openid-connect	oidc-usermodel-attribute-mapper	\N	4027eeb6-c7ad-4116-904b-a2df4e36b9e8
df8af3a8-e5e9-4535-912c-09f1a91347ef	groups	openid-connect	oidc-usermodel-realm-role-mapper	\N	4027eeb6-c7ad-4116-904b-a2df4e36b9e8
5ff22b02-937c-47c4-b4ac-b55ec6724241	acr loa level	openid-connect	oidc-acr-mapper	\N	3f8efb2a-e473-45eb-be11-7440abc689ac
ee04a2aa-bc9b-4698-be98-ae900c54a208	auth_time	openid-connect	oidc-usersessionmodel-note-mapper	\N	7ae1f834-5642-46dd-8e8c-15e04b03855b
d78504d5-5e7c-42d5-9f93-744ebd009aca	sub	openid-connect	oidc-sub-mapper	\N	7ae1f834-5642-46dd-8e8c-15e04b03855b
27051252-058f-4854-9a59-34386e89d25e	organization	openid-connect	oidc-organization-membership-mapper	\N	ed5212a6-310a-4582-9c92-3610bf722f23
5cab556f-cacd-477d-b486-efa5d4310e87	audience resolve	openid-connect	oidc-audience-resolve-mapper	9f5333a7-931d-4663-b07d-c89928cd6498	\N
e6cefbdd-f281-4548-af42-05f3a6e04b0f	role list	saml	saml-role-list-mapper	\N	7af22446-a644-47ee-b4ff-50ae92fa75b5
23e52006-ce52-4ac3-8a6e-96d03a30aa3a	organization	saml	saml-organization-membership-mapper	\N	4f907d9a-50f0-4f21-a8bc-abba39a00872
05c537eb-1f01-45b3-8fa8-7298ad3e69bc	full name	openid-connect	oidc-full-name-mapper	\N	a4ed44cb-bcd9-4403-bdf6-ff361131c239
fdc38ac3-2762-4ee4-a3c8-25faaac0725c	family name	openid-connect	oidc-usermodel-attribute-mapper	\N	a4ed44cb-bcd9-4403-bdf6-ff361131c239
41d54dc5-b448-4a28-8516-1578bdb32bb5	given name	openid-connect	oidc-usermodel-attribute-mapper	\N	a4ed44cb-bcd9-4403-bdf6-ff361131c239
b47587cb-93d5-4dd4-8148-2ff5226c9cd8	middle name	openid-connect	oidc-usermodel-attribute-mapper	\N	a4ed44cb-bcd9-4403-bdf6-ff361131c239
1da36113-bba4-483d-8a23-96960164c7ed	nickname	openid-connect	oidc-usermodel-attribute-mapper	\N	a4ed44cb-bcd9-4403-bdf6-ff361131c239
8e38a79d-0911-4a21-906d-02f86c21fdc9	username	openid-connect	oidc-usermodel-attribute-mapper	\N	a4ed44cb-bcd9-4403-bdf6-ff361131c239
b58ad612-141a-49ad-8400-d27b1d8cc4e4	profile	openid-connect	oidc-usermodel-attribute-mapper	\N	a4ed44cb-bcd9-4403-bdf6-ff361131c239
4a9db85e-27d1-4577-8872-4c12631ef83f	picture	openid-connect	oidc-usermodel-attribute-mapper	\N	a4ed44cb-bcd9-4403-bdf6-ff361131c239
3ac19d77-8cf6-4bdc-bc79-c896a4250977	website	openid-connect	oidc-usermodel-attribute-mapper	\N	a4ed44cb-bcd9-4403-bdf6-ff361131c239
2467542c-da6b-464a-bb92-a57274e0e674	gender	openid-connect	oidc-usermodel-attribute-mapper	\N	a4ed44cb-bcd9-4403-bdf6-ff361131c239
2b3cdf57-5161-42d8-9e1e-1f6d25270f1d	birthdate	openid-connect	oidc-usermodel-attribute-mapper	\N	a4ed44cb-bcd9-4403-bdf6-ff361131c239
9128adb1-7908-46d3-b995-9b54a5521d84	zoneinfo	openid-connect	oidc-usermodel-attribute-mapper	\N	a4ed44cb-bcd9-4403-bdf6-ff361131c239
93d6da11-4116-40fc-8ca5-eb165832f1ef	locale	openid-connect	oidc-usermodel-attribute-mapper	\N	a4ed44cb-bcd9-4403-bdf6-ff361131c239
84c3dea1-12be-4628-8b21-676249a709d2	updated at	openid-connect	oidc-usermodel-attribute-mapper	\N	a4ed44cb-bcd9-4403-bdf6-ff361131c239
6efe0a22-4eef-41ad-920d-a41e1c0041bb	email	openid-connect	oidc-usermodel-attribute-mapper	\N	1b300f54-3ac9-44c4-ad0b-414957f47ebc
4ce59262-19a9-4b65-bf28-a8e94d84fd05	email verified	openid-connect	oidc-usermodel-property-mapper	\N	1b300f54-3ac9-44c4-ad0b-414957f47ebc
1c6af103-90d0-43ca-82bc-77ae2bf92ee3	address	openid-connect	oidc-address-mapper	\N	6bc2853a-a28e-44de-9036-0e505be14d79
c64bf231-8655-4c8c-b4ba-8def5f85f989	phone number	openid-connect	oidc-usermodel-attribute-mapper	\N	b8041d7f-a6a0-4d56-aad4-33750056ee31
41e02911-5345-40f5-b5cf-6c0d02c6b1bd	phone number verified	openid-connect	oidc-usermodel-attribute-mapper	\N	b8041d7f-a6a0-4d56-aad4-33750056ee31
73d2ff7b-72e9-4fe0-b980-3bf7e02beba1	realm roles	openid-connect	oidc-usermodel-realm-role-mapper	\N	e47d3371-e4be-45f3-89aa-4b74f1f87832
a141159a-c4bb-4139-bd5e-01ed38ee76b5	client roles	openid-connect	oidc-usermodel-client-role-mapper	\N	e47d3371-e4be-45f3-89aa-4b74f1f87832
b94b8c0f-1956-4263-820e-5e818bb96eda	audience resolve	openid-connect	oidc-audience-resolve-mapper	\N	e47d3371-e4be-45f3-89aa-4b74f1f87832
6645d644-50ec-4f70-8ca7-c03ecaf20f1d	allowed web origins	openid-connect	oidc-allowed-origins-mapper	\N	70c49995-ea6d-498b-bba4-7b4a51b46fe9
fc01b1df-49ea-4c07-a773-c6e3f6a8439b	upn	openid-connect	oidc-usermodel-attribute-mapper	\N	cc0c3d1c-4e90-47aa-aae0-44f1dcf89a15
07c1e5a5-59e0-407f-93da-197d67d690b2	groups	openid-connect	oidc-usermodel-realm-role-mapper	\N	cc0c3d1c-4e90-47aa-aae0-44f1dcf89a15
74bd57d2-738e-4be8-9626-84458ee2c212	acr loa level	openid-connect	oidc-acr-mapper	\N	f3951ff7-42a3-4fd7-9219-c8aecfb52169
a431d8cc-a54f-4fd1-b34a-5300bc5c4b15	auth_time	openid-connect	oidc-usersessionmodel-note-mapper	\N	a8710cae-609f-4d07-b2e8-bf878bb356d3
c30cd5bb-a8de-42d6-b2fb-3f38da22144c	sub	openid-connect	oidc-sub-mapper	\N	a8710cae-609f-4d07-b2e8-bf878bb356d3
67125dd3-542a-4e08-a69a-e591bb46a563	organization	openid-connect	oidc-organization-membership-mapper	\N	92d3c51f-da77-4ec0-a58a-3cf9a81d8bd1
8681c5b7-5feb-4132-a35e-4e630add324f	locale	openid-connect	oidc-usermodel-attribute-mapper	94df3d2f-7a99-4794-92f9-c879ceea36a0	\N
f35b445c-1d44-48d7-9283-75d63a30f65a	Client ID	openid-connect	oidc-usersessionmodel-note-mapper	40f8f713-e1c4-4e9d-a804-2ec22fb3d118	\N
ea020ab1-4e2b-4d41-b788-2a4dbe30544e	Client Host	openid-connect	oidc-usersessionmodel-note-mapper	40f8f713-e1c4-4e9d-a804-2ec22fb3d118	\N
fb3d4dd3-f723-491e-b72f-f57c9a003188	Client IP Address	openid-connect	oidc-usersessionmodel-note-mapper	40f8f713-e1c4-4e9d-a804-2ec22fb3d118	\N
ceeccb1b-5a94-4cad-91d1-ee21583adfcc	Client ID	openid-connect	oidc-usersessionmodel-note-mapper	ab4df486-dff6-488a-aa26-56cccddaf5fc	\N
6d598011-51e5-4c59-b0cf-757a6d308c8e	Client Host	openid-connect	oidc-usersessionmodel-note-mapper	ab4df486-dff6-488a-aa26-56cccddaf5fc	\N
cf8f7561-e534-49e0-b555-e4b55c3cf6e1	Client IP Address	openid-connect	oidc-usersessionmodel-note-mapper	ab4df486-dff6-488a-aa26-56cccddaf5fc	\N
\.


--
-- Data for Name: protocol_mapper_config; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.protocol_mapper_config (protocol_mapper_id, value, name) FROM stdin;
6c48de52-8a8f-4617-b95f-23e48cd446d8	true	introspection.token.claim
6c48de52-8a8f-4617-b95f-23e48cd446d8	true	userinfo.token.claim
6c48de52-8a8f-4617-b95f-23e48cd446d8	locale	user.attribute
6c48de52-8a8f-4617-b95f-23e48cd446d8	true	id.token.claim
6c48de52-8a8f-4617-b95f-23e48cd446d8	true	access.token.claim
6c48de52-8a8f-4617-b95f-23e48cd446d8	locale	claim.name
6c48de52-8a8f-4617-b95f-23e48cd446d8	String	jsonType.label
d0e8d539-7524-4c6f-8cc5-ed57de473bac	false	single
d0e8d539-7524-4c6f-8cc5-ed57de473bac	Basic	attribute.nameformat
d0e8d539-7524-4c6f-8cc5-ed57de473bac	Role	attribute.name
07dff9f4-25ad-42c4-ac71-e2f463ce37a2	true	introspection.token.claim
07dff9f4-25ad-42c4-ac71-e2f463ce37a2	true	userinfo.token.claim
07dff9f4-25ad-42c4-ac71-e2f463ce37a2	website	user.attribute
07dff9f4-25ad-42c4-ac71-e2f463ce37a2	true	id.token.claim
07dff9f4-25ad-42c4-ac71-e2f463ce37a2	true	access.token.claim
07dff9f4-25ad-42c4-ac71-e2f463ce37a2	website	claim.name
07dff9f4-25ad-42c4-ac71-e2f463ce37a2	String	jsonType.label
240109d7-f1ed-4e7d-835f-4bb363cf65ec	true	introspection.token.claim
240109d7-f1ed-4e7d-835f-4bb363cf65ec	true	userinfo.token.claim
240109d7-f1ed-4e7d-835f-4bb363cf65ec	true	id.token.claim
240109d7-f1ed-4e7d-835f-4bb363cf65ec	true	access.token.claim
2d203ee8-69b6-47bd-8c67-8c5430f06c54	true	introspection.token.claim
2d203ee8-69b6-47bd-8c67-8c5430f06c54	true	userinfo.token.claim
2d203ee8-69b6-47bd-8c67-8c5430f06c54	profile	user.attribute
2d203ee8-69b6-47bd-8c67-8c5430f06c54	true	id.token.claim
2d203ee8-69b6-47bd-8c67-8c5430f06c54	true	access.token.claim
2d203ee8-69b6-47bd-8c67-8c5430f06c54	profile	claim.name
2d203ee8-69b6-47bd-8c67-8c5430f06c54	String	jsonType.label
33bb7496-5329-4f7c-94ca-37c11cb19b15	true	introspection.token.claim
33bb7496-5329-4f7c-94ca-37c11cb19b15	true	userinfo.token.claim
33bb7496-5329-4f7c-94ca-37c11cb19b15	username	user.attribute
33bb7496-5329-4f7c-94ca-37c11cb19b15	true	id.token.claim
33bb7496-5329-4f7c-94ca-37c11cb19b15	true	access.token.claim
33bb7496-5329-4f7c-94ca-37c11cb19b15	preferred_username	claim.name
33bb7496-5329-4f7c-94ca-37c11cb19b15	String	jsonType.label
3c3a1307-2400-4ef1-86f3-6b9214bc5eba	true	introspection.token.claim
3c3a1307-2400-4ef1-86f3-6b9214bc5eba	true	userinfo.token.claim
3c3a1307-2400-4ef1-86f3-6b9214bc5eba	firstName	user.attribute
3c3a1307-2400-4ef1-86f3-6b9214bc5eba	true	id.token.claim
3c3a1307-2400-4ef1-86f3-6b9214bc5eba	true	access.token.claim
3c3a1307-2400-4ef1-86f3-6b9214bc5eba	given_name	claim.name
3c3a1307-2400-4ef1-86f3-6b9214bc5eba	String	jsonType.label
3fc4ba98-8c1f-48df-a677-b7c80224173a	true	introspection.token.claim
3fc4ba98-8c1f-48df-a677-b7c80224173a	true	userinfo.token.claim
3fc4ba98-8c1f-48df-a677-b7c80224173a	picture	user.attribute
3fc4ba98-8c1f-48df-a677-b7c80224173a	true	id.token.claim
3fc4ba98-8c1f-48df-a677-b7c80224173a	true	access.token.claim
3fc4ba98-8c1f-48df-a677-b7c80224173a	picture	claim.name
3fc4ba98-8c1f-48df-a677-b7c80224173a	String	jsonType.label
61eeb4b5-e07e-44de-b090-64577cca0ebb	true	introspection.token.claim
61eeb4b5-e07e-44de-b090-64577cca0ebb	true	userinfo.token.claim
61eeb4b5-e07e-44de-b090-64577cca0ebb	birthdate	user.attribute
61eeb4b5-e07e-44de-b090-64577cca0ebb	true	id.token.claim
61eeb4b5-e07e-44de-b090-64577cca0ebb	true	access.token.claim
61eeb4b5-e07e-44de-b090-64577cca0ebb	birthdate	claim.name
61eeb4b5-e07e-44de-b090-64577cca0ebb	String	jsonType.label
7b9892d6-e7b9-4454-95ff-542ccd6bfde4	true	introspection.token.claim
7b9892d6-e7b9-4454-95ff-542ccd6bfde4	true	userinfo.token.claim
7b9892d6-e7b9-4454-95ff-542ccd6bfde4	zoneinfo	user.attribute
7b9892d6-e7b9-4454-95ff-542ccd6bfde4	true	id.token.claim
7b9892d6-e7b9-4454-95ff-542ccd6bfde4	true	access.token.claim
7b9892d6-e7b9-4454-95ff-542ccd6bfde4	zoneinfo	claim.name
7b9892d6-e7b9-4454-95ff-542ccd6bfde4	String	jsonType.label
aa6aefde-f0a8-49f9-a9a7-8ffc081932c0	true	introspection.token.claim
aa6aefde-f0a8-49f9-a9a7-8ffc081932c0	true	userinfo.token.claim
aa6aefde-f0a8-49f9-a9a7-8ffc081932c0	updatedAt	user.attribute
aa6aefde-f0a8-49f9-a9a7-8ffc081932c0	true	id.token.claim
aa6aefde-f0a8-49f9-a9a7-8ffc081932c0	true	access.token.claim
aa6aefde-f0a8-49f9-a9a7-8ffc081932c0	updated_at	claim.name
aa6aefde-f0a8-49f9-a9a7-8ffc081932c0	long	jsonType.label
c1064f0e-24d2-4afb-8479-2ea2dac85169	true	introspection.token.claim
c1064f0e-24d2-4afb-8479-2ea2dac85169	true	userinfo.token.claim
c1064f0e-24d2-4afb-8479-2ea2dac85169	nickname	user.attribute
c1064f0e-24d2-4afb-8479-2ea2dac85169	true	id.token.claim
c1064f0e-24d2-4afb-8479-2ea2dac85169	true	access.token.claim
c1064f0e-24d2-4afb-8479-2ea2dac85169	nickname	claim.name
c1064f0e-24d2-4afb-8479-2ea2dac85169	String	jsonType.label
c1297fa4-d1fb-4ea4-962d-10458656c763	true	introspection.token.claim
c1297fa4-d1fb-4ea4-962d-10458656c763	true	userinfo.token.claim
c1297fa4-d1fb-4ea4-962d-10458656c763	lastName	user.attribute
c1297fa4-d1fb-4ea4-962d-10458656c763	true	id.token.claim
c1297fa4-d1fb-4ea4-962d-10458656c763	true	access.token.claim
c1297fa4-d1fb-4ea4-962d-10458656c763	family_name	claim.name
c1297fa4-d1fb-4ea4-962d-10458656c763	String	jsonType.label
cedc997d-bbb2-490a-90df-61705ca423dd	true	introspection.token.claim
cedc997d-bbb2-490a-90df-61705ca423dd	true	userinfo.token.claim
cedc997d-bbb2-490a-90df-61705ca423dd	locale	user.attribute
cedc997d-bbb2-490a-90df-61705ca423dd	true	id.token.claim
cedc997d-bbb2-490a-90df-61705ca423dd	true	access.token.claim
cedc997d-bbb2-490a-90df-61705ca423dd	locale	claim.name
cedc997d-bbb2-490a-90df-61705ca423dd	String	jsonType.label
de18d987-457b-4cce-8d7b-efba1c91e738	true	introspection.token.claim
de18d987-457b-4cce-8d7b-efba1c91e738	true	userinfo.token.claim
de18d987-457b-4cce-8d7b-efba1c91e738	gender	user.attribute
de18d987-457b-4cce-8d7b-efba1c91e738	true	id.token.claim
de18d987-457b-4cce-8d7b-efba1c91e738	true	access.token.claim
de18d987-457b-4cce-8d7b-efba1c91e738	gender	claim.name
de18d987-457b-4cce-8d7b-efba1c91e738	String	jsonType.label
f457a039-5bfe-4d4c-a693-a682e36597ab	true	introspection.token.claim
f457a039-5bfe-4d4c-a693-a682e36597ab	true	userinfo.token.claim
f457a039-5bfe-4d4c-a693-a682e36597ab	middleName	user.attribute
f457a039-5bfe-4d4c-a693-a682e36597ab	true	id.token.claim
f457a039-5bfe-4d4c-a693-a682e36597ab	true	access.token.claim
f457a039-5bfe-4d4c-a693-a682e36597ab	middle_name	claim.name
f457a039-5bfe-4d4c-a693-a682e36597ab	String	jsonType.label
6e9c10d6-f745-478f-9e5f-5c873fbb6562	true	introspection.token.claim
6e9c10d6-f745-478f-9e5f-5c873fbb6562	true	userinfo.token.claim
6e9c10d6-f745-478f-9e5f-5c873fbb6562	email	user.attribute
6e9c10d6-f745-478f-9e5f-5c873fbb6562	true	id.token.claim
6e9c10d6-f745-478f-9e5f-5c873fbb6562	true	access.token.claim
6e9c10d6-f745-478f-9e5f-5c873fbb6562	email	claim.name
6e9c10d6-f745-478f-9e5f-5c873fbb6562	String	jsonType.label
86dec864-8243-4c80-86d8-eee4a50faca8	true	introspection.token.claim
86dec864-8243-4c80-86d8-eee4a50faca8	true	userinfo.token.claim
86dec864-8243-4c80-86d8-eee4a50faca8	emailVerified	user.attribute
86dec864-8243-4c80-86d8-eee4a50faca8	true	id.token.claim
86dec864-8243-4c80-86d8-eee4a50faca8	true	access.token.claim
86dec864-8243-4c80-86d8-eee4a50faca8	email_verified	claim.name
86dec864-8243-4c80-86d8-eee4a50faca8	boolean	jsonType.label
9952b570-5458-4092-b0b4-90b7735df12f	formatted	user.attribute.formatted
9952b570-5458-4092-b0b4-90b7735df12f	country	user.attribute.country
9952b570-5458-4092-b0b4-90b7735df12f	true	introspection.token.claim
9952b570-5458-4092-b0b4-90b7735df12f	postal_code	user.attribute.postal_code
9952b570-5458-4092-b0b4-90b7735df12f	true	userinfo.token.claim
9952b570-5458-4092-b0b4-90b7735df12f	street	user.attribute.street
9952b570-5458-4092-b0b4-90b7735df12f	true	id.token.claim
9952b570-5458-4092-b0b4-90b7735df12f	region	user.attribute.region
9952b570-5458-4092-b0b4-90b7735df12f	true	access.token.claim
9952b570-5458-4092-b0b4-90b7735df12f	locality	user.attribute.locality
53e44793-7974-4b15-9b24-248ebeb0f68b	true	introspection.token.claim
53e44793-7974-4b15-9b24-248ebeb0f68b	true	userinfo.token.claim
53e44793-7974-4b15-9b24-248ebeb0f68b	phoneNumberVerified	user.attribute
53e44793-7974-4b15-9b24-248ebeb0f68b	true	id.token.claim
53e44793-7974-4b15-9b24-248ebeb0f68b	true	access.token.claim
53e44793-7974-4b15-9b24-248ebeb0f68b	phone_number_verified	claim.name
53e44793-7974-4b15-9b24-248ebeb0f68b	boolean	jsonType.label
5ad6c02e-1820-4ddf-9ad7-cd464176aacb	true	introspection.token.claim
5ad6c02e-1820-4ddf-9ad7-cd464176aacb	true	userinfo.token.claim
5ad6c02e-1820-4ddf-9ad7-cd464176aacb	phoneNumber	user.attribute
5ad6c02e-1820-4ddf-9ad7-cd464176aacb	true	id.token.claim
5ad6c02e-1820-4ddf-9ad7-cd464176aacb	true	access.token.claim
5ad6c02e-1820-4ddf-9ad7-cd464176aacb	phone_number	claim.name
5ad6c02e-1820-4ddf-9ad7-cd464176aacb	String	jsonType.label
9f367bce-6f39-46e6-a1ce-92cd1cf9a27f	true	introspection.token.claim
9f367bce-6f39-46e6-a1ce-92cd1cf9a27f	true	multivalued
9f367bce-6f39-46e6-a1ce-92cd1cf9a27f	foo	user.attribute
9f367bce-6f39-46e6-a1ce-92cd1cf9a27f	true	access.token.claim
9f367bce-6f39-46e6-a1ce-92cd1cf9a27f	resource_access.${client_id}.roles	claim.name
9f367bce-6f39-46e6-a1ce-92cd1cf9a27f	String	jsonType.label
a4fb0211-2cbd-40b5-b191-a4800d5357b6	true	introspection.token.claim
a4fb0211-2cbd-40b5-b191-a4800d5357b6	true	multivalued
a4fb0211-2cbd-40b5-b191-a4800d5357b6	foo	user.attribute
a4fb0211-2cbd-40b5-b191-a4800d5357b6	true	access.token.claim
a4fb0211-2cbd-40b5-b191-a4800d5357b6	realm_access.roles	claim.name
a4fb0211-2cbd-40b5-b191-a4800d5357b6	String	jsonType.label
b3852362-2ff1-4463-b328-22bcb81358f7	true	introspection.token.claim
b3852362-2ff1-4463-b328-22bcb81358f7	true	access.token.claim
6408bc89-5a42-4cca-a71d-00f3609decdc	true	introspection.token.claim
6408bc89-5a42-4cca-a71d-00f3609decdc	true	access.token.claim
c5a0fe7b-eb5a-4e40-82dc-71eaaeaee014	true	introspection.token.claim
c5a0fe7b-eb5a-4e40-82dc-71eaaeaee014	true	userinfo.token.claim
c5a0fe7b-eb5a-4e40-82dc-71eaaeaee014	username	user.attribute
c5a0fe7b-eb5a-4e40-82dc-71eaaeaee014	true	id.token.claim
c5a0fe7b-eb5a-4e40-82dc-71eaaeaee014	true	access.token.claim
c5a0fe7b-eb5a-4e40-82dc-71eaaeaee014	upn	claim.name
c5a0fe7b-eb5a-4e40-82dc-71eaaeaee014	String	jsonType.label
df8af3a8-e5e9-4535-912c-09f1a91347ef	true	introspection.token.claim
df8af3a8-e5e9-4535-912c-09f1a91347ef	true	multivalued
df8af3a8-e5e9-4535-912c-09f1a91347ef	foo	user.attribute
df8af3a8-e5e9-4535-912c-09f1a91347ef	true	id.token.claim
df8af3a8-e5e9-4535-912c-09f1a91347ef	true	access.token.claim
df8af3a8-e5e9-4535-912c-09f1a91347ef	groups	claim.name
df8af3a8-e5e9-4535-912c-09f1a91347ef	String	jsonType.label
5ff22b02-937c-47c4-b4ac-b55ec6724241	true	introspection.token.claim
5ff22b02-937c-47c4-b4ac-b55ec6724241	true	id.token.claim
5ff22b02-937c-47c4-b4ac-b55ec6724241	true	access.token.claim
d78504d5-5e7c-42d5-9f93-744ebd009aca	true	introspection.token.claim
d78504d5-5e7c-42d5-9f93-744ebd009aca	true	access.token.claim
ee04a2aa-bc9b-4698-be98-ae900c54a208	AUTH_TIME	user.session.note
ee04a2aa-bc9b-4698-be98-ae900c54a208	true	introspection.token.claim
ee04a2aa-bc9b-4698-be98-ae900c54a208	true	id.token.claim
ee04a2aa-bc9b-4698-be98-ae900c54a208	true	access.token.claim
ee04a2aa-bc9b-4698-be98-ae900c54a208	auth_time	claim.name
ee04a2aa-bc9b-4698-be98-ae900c54a208	long	jsonType.label
27051252-058f-4854-9a59-34386e89d25e	true	introspection.token.claim
27051252-058f-4854-9a59-34386e89d25e	true	multivalued
27051252-058f-4854-9a59-34386e89d25e	true	id.token.claim
27051252-058f-4854-9a59-34386e89d25e	true	access.token.claim
27051252-058f-4854-9a59-34386e89d25e	organization	claim.name
27051252-058f-4854-9a59-34386e89d25e	String	jsonType.label
e6cefbdd-f281-4548-af42-05f3a6e04b0f	false	single
e6cefbdd-f281-4548-af42-05f3a6e04b0f	Basic	attribute.nameformat
e6cefbdd-f281-4548-af42-05f3a6e04b0f	Role	attribute.name
05c537eb-1f01-45b3-8fa8-7298ad3e69bc	true	introspection.token.claim
05c537eb-1f01-45b3-8fa8-7298ad3e69bc	true	userinfo.token.claim
05c537eb-1f01-45b3-8fa8-7298ad3e69bc	true	id.token.claim
05c537eb-1f01-45b3-8fa8-7298ad3e69bc	true	access.token.claim
1da36113-bba4-483d-8a23-96960164c7ed	true	introspection.token.claim
1da36113-bba4-483d-8a23-96960164c7ed	true	userinfo.token.claim
1da36113-bba4-483d-8a23-96960164c7ed	nickname	user.attribute
1da36113-bba4-483d-8a23-96960164c7ed	true	id.token.claim
1da36113-bba4-483d-8a23-96960164c7ed	true	access.token.claim
1da36113-bba4-483d-8a23-96960164c7ed	nickname	claim.name
1da36113-bba4-483d-8a23-96960164c7ed	String	jsonType.label
2467542c-da6b-464a-bb92-a57274e0e674	true	introspection.token.claim
2467542c-da6b-464a-bb92-a57274e0e674	true	userinfo.token.claim
2467542c-da6b-464a-bb92-a57274e0e674	gender	user.attribute
2467542c-da6b-464a-bb92-a57274e0e674	true	id.token.claim
2467542c-da6b-464a-bb92-a57274e0e674	true	access.token.claim
2467542c-da6b-464a-bb92-a57274e0e674	gender	claim.name
2467542c-da6b-464a-bb92-a57274e0e674	String	jsonType.label
2b3cdf57-5161-42d8-9e1e-1f6d25270f1d	true	introspection.token.claim
2b3cdf57-5161-42d8-9e1e-1f6d25270f1d	true	userinfo.token.claim
2b3cdf57-5161-42d8-9e1e-1f6d25270f1d	birthdate	user.attribute
2b3cdf57-5161-42d8-9e1e-1f6d25270f1d	true	id.token.claim
2b3cdf57-5161-42d8-9e1e-1f6d25270f1d	true	access.token.claim
2b3cdf57-5161-42d8-9e1e-1f6d25270f1d	birthdate	claim.name
2b3cdf57-5161-42d8-9e1e-1f6d25270f1d	String	jsonType.label
3ac19d77-8cf6-4bdc-bc79-c896a4250977	true	introspection.token.claim
3ac19d77-8cf6-4bdc-bc79-c896a4250977	true	userinfo.token.claim
3ac19d77-8cf6-4bdc-bc79-c896a4250977	website	user.attribute
3ac19d77-8cf6-4bdc-bc79-c896a4250977	true	id.token.claim
3ac19d77-8cf6-4bdc-bc79-c896a4250977	true	access.token.claim
3ac19d77-8cf6-4bdc-bc79-c896a4250977	website	claim.name
3ac19d77-8cf6-4bdc-bc79-c896a4250977	String	jsonType.label
41d54dc5-b448-4a28-8516-1578bdb32bb5	true	introspection.token.claim
41d54dc5-b448-4a28-8516-1578bdb32bb5	true	userinfo.token.claim
41d54dc5-b448-4a28-8516-1578bdb32bb5	firstName	user.attribute
41d54dc5-b448-4a28-8516-1578bdb32bb5	true	id.token.claim
41d54dc5-b448-4a28-8516-1578bdb32bb5	true	access.token.claim
41d54dc5-b448-4a28-8516-1578bdb32bb5	given_name	claim.name
41d54dc5-b448-4a28-8516-1578bdb32bb5	String	jsonType.label
4a9db85e-27d1-4577-8872-4c12631ef83f	true	introspection.token.claim
4a9db85e-27d1-4577-8872-4c12631ef83f	true	userinfo.token.claim
4a9db85e-27d1-4577-8872-4c12631ef83f	picture	user.attribute
4a9db85e-27d1-4577-8872-4c12631ef83f	true	id.token.claim
4a9db85e-27d1-4577-8872-4c12631ef83f	true	access.token.claim
4a9db85e-27d1-4577-8872-4c12631ef83f	picture	claim.name
4a9db85e-27d1-4577-8872-4c12631ef83f	String	jsonType.label
84c3dea1-12be-4628-8b21-676249a709d2	true	introspection.token.claim
84c3dea1-12be-4628-8b21-676249a709d2	true	userinfo.token.claim
84c3dea1-12be-4628-8b21-676249a709d2	updatedAt	user.attribute
84c3dea1-12be-4628-8b21-676249a709d2	true	id.token.claim
84c3dea1-12be-4628-8b21-676249a709d2	true	access.token.claim
84c3dea1-12be-4628-8b21-676249a709d2	updated_at	claim.name
84c3dea1-12be-4628-8b21-676249a709d2	long	jsonType.label
8e38a79d-0911-4a21-906d-02f86c21fdc9	true	introspection.token.claim
8e38a79d-0911-4a21-906d-02f86c21fdc9	true	userinfo.token.claim
8e38a79d-0911-4a21-906d-02f86c21fdc9	username	user.attribute
8e38a79d-0911-4a21-906d-02f86c21fdc9	true	id.token.claim
8e38a79d-0911-4a21-906d-02f86c21fdc9	true	access.token.claim
8e38a79d-0911-4a21-906d-02f86c21fdc9	preferred_username	claim.name
8e38a79d-0911-4a21-906d-02f86c21fdc9	String	jsonType.label
9128adb1-7908-46d3-b995-9b54a5521d84	true	introspection.token.claim
9128adb1-7908-46d3-b995-9b54a5521d84	true	userinfo.token.claim
9128adb1-7908-46d3-b995-9b54a5521d84	zoneinfo	user.attribute
9128adb1-7908-46d3-b995-9b54a5521d84	true	id.token.claim
9128adb1-7908-46d3-b995-9b54a5521d84	true	access.token.claim
9128adb1-7908-46d3-b995-9b54a5521d84	zoneinfo	claim.name
9128adb1-7908-46d3-b995-9b54a5521d84	String	jsonType.label
93d6da11-4116-40fc-8ca5-eb165832f1ef	true	introspection.token.claim
93d6da11-4116-40fc-8ca5-eb165832f1ef	true	userinfo.token.claim
93d6da11-4116-40fc-8ca5-eb165832f1ef	locale	user.attribute
93d6da11-4116-40fc-8ca5-eb165832f1ef	true	id.token.claim
93d6da11-4116-40fc-8ca5-eb165832f1ef	true	access.token.claim
93d6da11-4116-40fc-8ca5-eb165832f1ef	locale	claim.name
93d6da11-4116-40fc-8ca5-eb165832f1ef	String	jsonType.label
b47587cb-93d5-4dd4-8148-2ff5226c9cd8	true	introspection.token.claim
b47587cb-93d5-4dd4-8148-2ff5226c9cd8	true	userinfo.token.claim
b47587cb-93d5-4dd4-8148-2ff5226c9cd8	middleName	user.attribute
b47587cb-93d5-4dd4-8148-2ff5226c9cd8	true	id.token.claim
b47587cb-93d5-4dd4-8148-2ff5226c9cd8	true	access.token.claim
b47587cb-93d5-4dd4-8148-2ff5226c9cd8	middle_name	claim.name
b47587cb-93d5-4dd4-8148-2ff5226c9cd8	String	jsonType.label
b58ad612-141a-49ad-8400-d27b1d8cc4e4	true	introspection.token.claim
b58ad612-141a-49ad-8400-d27b1d8cc4e4	true	userinfo.token.claim
b58ad612-141a-49ad-8400-d27b1d8cc4e4	profile	user.attribute
b58ad612-141a-49ad-8400-d27b1d8cc4e4	true	id.token.claim
b58ad612-141a-49ad-8400-d27b1d8cc4e4	true	access.token.claim
b58ad612-141a-49ad-8400-d27b1d8cc4e4	profile	claim.name
b58ad612-141a-49ad-8400-d27b1d8cc4e4	String	jsonType.label
fdc38ac3-2762-4ee4-a3c8-25faaac0725c	true	introspection.token.claim
fdc38ac3-2762-4ee4-a3c8-25faaac0725c	true	userinfo.token.claim
fdc38ac3-2762-4ee4-a3c8-25faaac0725c	lastName	user.attribute
fdc38ac3-2762-4ee4-a3c8-25faaac0725c	true	id.token.claim
fdc38ac3-2762-4ee4-a3c8-25faaac0725c	true	access.token.claim
fdc38ac3-2762-4ee4-a3c8-25faaac0725c	family_name	claim.name
fdc38ac3-2762-4ee4-a3c8-25faaac0725c	String	jsonType.label
4ce59262-19a9-4b65-bf28-a8e94d84fd05	true	introspection.token.claim
4ce59262-19a9-4b65-bf28-a8e94d84fd05	true	userinfo.token.claim
4ce59262-19a9-4b65-bf28-a8e94d84fd05	emailVerified	user.attribute
4ce59262-19a9-4b65-bf28-a8e94d84fd05	true	id.token.claim
4ce59262-19a9-4b65-bf28-a8e94d84fd05	true	access.token.claim
4ce59262-19a9-4b65-bf28-a8e94d84fd05	email_verified	claim.name
4ce59262-19a9-4b65-bf28-a8e94d84fd05	boolean	jsonType.label
6efe0a22-4eef-41ad-920d-a41e1c0041bb	true	introspection.token.claim
6efe0a22-4eef-41ad-920d-a41e1c0041bb	true	userinfo.token.claim
6efe0a22-4eef-41ad-920d-a41e1c0041bb	email	user.attribute
6efe0a22-4eef-41ad-920d-a41e1c0041bb	true	id.token.claim
6efe0a22-4eef-41ad-920d-a41e1c0041bb	true	access.token.claim
6efe0a22-4eef-41ad-920d-a41e1c0041bb	email	claim.name
6efe0a22-4eef-41ad-920d-a41e1c0041bb	String	jsonType.label
1c6af103-90d0-43ca-82bc-77ae2bf92ee3	formatted	user.attribute.formatted
1c6af103-90d0-43ca-82bc-77ae2bf92ee3	country	user.attribute.country
1c6af103-90d0-43ca-82bc-77ae2bf92ee3	true	introspection.token.claim
1c6af103-90d0-43ca-82bc-77ae2bf92ee3	postal_code	user.attribute.postal_code
1c6af103-90d0-43ca-82bc-77ae2bf92ee3	true	userinfo.token.claim
1c6af103-90d0-43ca-82bc-77ae2bf92ee3	street	user.attribute.street
1c6af103-90d0-43ca-82bc-77ae2bf92ee3	true	id.token.claim
1c6af103-90d0-43ca-82bc-77ae2bf92ee3	region	user.attribute.region
1c6af103-90d0-43ca-82bc-77ae2bf92ee3	true	access.token.claim
1c6af103-90d0-43ca-82bc-77ae2bf92ee3	locality	user.attribute.locality
41e02911-5345-40f5-b5cf-6c0d02c6b1bd	true	introspection.token.claim
41e02911-5345-40f5-b5cf-6c0d02c6b1bd	true	userinfo.token.claim
41e02911-5345-40f5-b5cf-6c0d02c6b1bd	phoneNumberVerified	user.attribute
41e02911-5345-40f5-b5cf-6c0d02c6b1bd	true	id.token.claim
41e02911-5345-40f5-b5cf-6c0d02c6b1bd	true	access.token.claim
41e02911-5345-40f5-b5cf-6c0d02c6b1bd	phone_number_verified	claim.name
41e02911-5345-40f5-b5cf-6c0d02c6b1bd	boolean	jsonType.label
c64bf231-8655-4c8c-b4ba-8def5f85f989	true	introspection.token.claim
c64bf231-8655-4c8c-b4ba-8def5f85f989	true	userinfo.token.claim
c64bf231-8655-4c8c-b4ba-8def5f85f989	phoneNumber	user.attribute
c64bf231-8655-4c8c-b4ba-8def5f85f989	true	id.token.claim
c64bf231-8655-4c8c-b4ba-8def5f85f989	true	access.token.claim
c64bf231-8655-4c8c-b4ba-8def5f85f989	phone_number	claim.name
c64bf231-8655-4c8c-b4ba-8def5f85f989	String	jsonType.label
73d2ff7b-72e9-4fe0-b980-3bf7e02beba1	true	introspection.token.claim
73d2ff7b-72e9-4fe0-b980-3bf7e02beba1	true	multivalued
73d2ff7b-72e9-4fe0-b980-3bf7e02beba1	foo	user.attribute
73d2ff7b-72e9-4fe0-b980-3bf7e02beba1	true	access.token.claim
73d2ff7b-72e9-4fe0-b980-3bf7e02beba1	realm_access.roles	claim.name
73d2ff7b-72e9-4fe0-b980-3bf7e02beba1	String	jsonType.label
a141159a-c4bb-4139-bd5e-01ed38ee76b5	true	introspection.token.claim
a141159a-c4bb-4139-bd5e-01ed38ee76b5	true	multivalued
a141159a-c4bb-4139-bd5e-01ed38ee76b5	foo	user.attribute
a141159a-c4bb-4139-bd5e-01ed38ee76b5	true	access.token.claim
a141159a-c4bb-4139-bd5e-01ed38ee76b5	resource_access.${client_id}.roles	claim.name
a141159a-c4bb-4139-bd5e-01ed38ee76b5	String	jsonType.label
b94b8c0f-1956-4263-820e-5e818bb96eda	true	introspection.token.claim
b94b8c0f-1956-4263-820e-5e818bb96eda	true	access.token.claim
6645d644-50ec-4f70-8ca7-c03ecaf20f1d	true	introspection.token.claim
6645d644-50ec-4f70-8ca7-c03ecaf20f1d	true	access.token.claim
07c1e5a5-59e0-407f-93da-197d67d690b2	true	introspection.token.claim
07c1e5a5-59e0-407f-93da-197d67d690b2	true	multivalued
07c1e5a5-59e0-407f-93da-197d67d690b2	foo	user.attribute
07c1e5a5-59e0-407f-93da-197d67d690b2	true	id.token.claim
07c1e5a5-59e0-407f-93da-197d67d690b2	true	access.token.claim
07c1e5a5-59e0-407f-93da-197d67d690b2	groups	claim.name
07c1e5a5-59e0-407f-93da-197d67d690b2	String	jsonType.label
fc01b1df-49ea-4c07-a773-c6e3f6a8439b	true	introspection.token.claim
fc01b1df-49ea-4c07-a773-c6e3f6a8439b	true	userinfo.token.claim
fc01b1df-49ea-4c07-a773-c6e3f6a8439b	username	user.attribute
fc01b1df-49ea-4c07-a773-c6e3f6a8439b	true	id.token.claim
fc01b1df-49ea-4c07-a773-c6e3f6a8439b	true	access.token.claim
fc01b1df-49ea-4c07-a773-c6e3f6a8439b	upn	claim.name
fc01b1df-49ea-4c07-a773-c6e3f6a8439b	String	jsonType.label
74bd57d2-738e-4be8-9626-84458ee2c212	true	introspection.token.claim
74bd57d2-738e-4be8-9626-84458ee2c212	true	id.token.claim
74bd57d2-738e-4be8-9626-84458ee2c212	true	access.token.claim
a431d8cc-a54f-4fd1-b34a-5300bc5c4b15	AUTH_TIME	user.session.note
a431d8cc-a54f-4fd1-b34a-5300bc5c4b15	true	introspection.token.claim
a431d8cc-a54f-4fd1-b34a-5300bc5c4b15	true	id.token.claim
a431d8cc-a54f-4fd1-b34a-5300bc5c4b15	true	access.token.claim
a431d8cc-a54f-4fd1-b34a-5300bc5c4b15	auth_time	claim.name
a431d8cc-a54f-4fd1-b34a-5300bc5c4b15	long	jsonType.label
c30cd5bb-a8de-42d6-b2fb-3f38da22144c	true	introspection.token.claim
c30cd5bb-a8de-42d6-b2fb-3f38da22144c	true	access.token.claim
67125dd3-542a-4e08-a69a-e591bb46a563	true	introspection.token.claim
67125dd3-542a-4e08-a69a-e591bb46a563	true	multivalued
67125dd3-542a-4e08-a69a-e591bb46a563	true	id.token.claim
67125dd3-542a-4e08-a69a-e591bb46a563	true	access.token.claim
67125dd3-542a-4e08-a69a-e591bb46a563	organization	claim.name
67125dd3-542a-4e08-a69a-e591bb46a563	String	jsonType.label
8681c5b7-5feb-4132-a35e-4e630add324f	true	introspection.token.claim
8681c5b7-5feb-4132-a35e-4e630add324f	true	userinfo.token.claim
8681c5b7-5feb-4132-a35e-4e630add324f	locale	user.attribute
8681c5b7-5feb-4132-a35e-4e630add324f	true	id.token.claim
8681c5b7-5feb-4132-a35e-4e630add324f	true	access.token.claim
8681c5b7-5feb-4132-a35e-4e630add324f	locale	claim.name
8681c5b7-5feb-4132-a35e-4e630add324f	String	jsonType.label
ea020ab1-4e2b-4d41-b788-2a4dbe30544e	clientHost	user.session.note
ea020ab1-4e2b-4d41-b788-2a4dbe30544e	true	introspection.token.claim
ea020ab1-4e2b-4d41-b788-2a4dbe30544e	true	id.token.claim
ea020ab1-4e2b-4d41-b788-2a4dbe30544e	true	access.token.claim
ea020ab1-4e2b-4d41-b788-2a4dbe30544e	clientHost	claim.name
ea020ab1-4e2b-4d41-b788-2a4dbe30544e	String	jsonType.label
f35b445c-1d44-48d7-9283-75d63a30f65a	client_id	user.session.note
f35b445c-1d44-48d7-9283-75d63a30f65a	true	introspection.token.claim
f35b445c-1d44-48d7-9283-75d63a30f65a	true	id.token.claim
f35b445c-1d44-48d7-9283-75d63a30f65a	true	access.token.claim
f35b445c-1d44-48d7-9283-75d63a30f65a	client_id	claim.name
f35b445c-1d44-48d7-9283-75d63a30f65a	String	jsonType.label
fb3d4dd3-f723-491e-b72f-f57c9a003188	clientAddress	user.session.note
fb3d4dd3-f723-491e-b72f-f57c9a003188	true	introspection.token.claim
fb3d4dd3-f723-491e-b72f-f57c9a003188	true	id.token.claim
fb3d4dd3-f723-491e-b72f-f57c9a003188	true	access.token.claim
fb3d4dd3-f723-491e-b72f-f57c9a003188	clientAddress	claim.name
fb3d4dd3-f723-491e-b72f-f57c9a003188	String	jsonType.label
6d598011-51e5-4c59-b0cf-757a6d308c8e	clientHost	user.session.note
6d598011-51e5-4c59-b0cf-757a6d308c8e	true	introspection.token.claim
6d598011-51e5-4c59-b0cf-757a6d308c8e	true	id.token.claim
6d598011-51e5-4c59-b0cf-757a6d308c8e	true	access.token.claim
6d598011-51e5-4c59-b0cf-757a6d308c8e	clientHost	claim.name
6d598011-51e5-4c59-b0cf-757a6d308c8e	String	jsonType.label
ceeccb1b-5a94-4cad-91d1-ee21583adfcc	client_id	user.session.note
ceeccb1b-5a94-4cad-91d1-ee21583adfcc	true	introspection.token.claim
ceeccb1b-5a94-4cad-91d1-ee21583adfcc	true	id.token.claim
ceeccb1b-5a94-4cad-91d1-ee21583adfcc	true	access.token.claim
ceeccb1b-5a94-4cad-91d1-ee21583adfcc	client_id	claim.name
ceeccb1b-5a94-4cad-91d1-ee21583adfcc	String	jsonType.label
cf8f7561-e534-49e0-b555-e4b55c3cf6e1	clientAddress	user.session.note
cf8f7561-e534-49e0-b555-e4b55c3cf6e1	true	introspection.token.claim
cf8f7561-e534-49e0-b555-e4b55c3cf6e1	true	id.token.claim
cf8f7561-e534-49e0-b555-e4b55c3cf6e1	true	access.token.claim
cf8f7561-e534-49e0-b555-e4b55c3cf6e1	clientAddress	claim.name
cf8f7561-e534-49e0-b555-e4b55c3cf6e1	String	jsonType.label
\.


--
-- Data for Name: realm; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.realm (id, access_code_lifespan, user_action_lifespan, access_token_lifespan, account_theme, admin_theme, email_theme, enabled, events_enabled, events_expiration, login_theme, name, not_before, password_policy, registration_allowed, remember_me, reset_password_allowed, social, ssl_required, sso_idle_timeout, sso_max_lifespan, update_profile_on_soc_login, verify_email, master_admin_client, login_lifespan, internationalization_enabled, default_locale, reg_email_as_username, admin_events_enabled, admin_events_details_enabled, edit_username_allowed, otp_policy_counter, otp_policy_window, otp_policy_period, otp_policy_digits, otp_policy_alg, otp_policy_type, browser_flow, registration_flow, direct_grant_flow, reset_credentials_flow, client_auth_flow, offline_session_idle_timeout, revoke_refresh_token, access_token_life_implicit, login_with_email_allowed, duplicate_emails_allowed, docker_auth_flow, refresh_token_max_reuse, allow_user_managed_access, sso_max_lifespan_remember_me, sso_idle_timeout_remember_me, default_role) FROM stdin;
5be18a3e-7181-4862-867b-45aff91b9b87	60	300	60	\N	\N	\N	t	f	0	\N	master	0	\N	f	f	f	f	EXTERNAL	1800	36000	f	f	58c02ea4-9114-4070-86ce-72fd450066cf	1800	f	\N	f	f	f	f	0	1	30	6	HmacSHA1	totp	5f8cbd27-a53c-4a85-bf5a-732d316a490a	1471d3f0-431f-4182-a32e-a9d1086fe058	984c5708-0406-4d68-80dc-6e8ecf273d35	4136924b-30e5-4f37-85bb-2784db2be1c2	4890f38e-a236-4160-9e34-0dded0a9f766	2592000	f	900	t	f	cc75ac9c-238d-48a0-9231-fdbd47609884	0	f	0	0	88007421-49af-4531-9b09-3025a88deb0f
21dfe33f-5923-4bfd-bc04-cf200e747656	60	300	300	\N	\N	\N	t	f	0	\N	local	0	\N	f	f	f	f	EXTERNAL	1800	36000	f	f	a21e795c-3dc5-4e25-9faf-13c6c3df2b02	1800	f	\N	f	f	f	f	0	1	30	6	HmacSHA1	totp	18f8930d-937f-4cfe-9759-456f27b2fbcd	1b430291-7568-4736-9f5d-41397ae77c84	901b8bca-2737-4d93-97af-1c0705c1f696	c03b6bd8-c892-4f47-98c7-884c4aa231f8	c4586673-35ac-4310-91ce-8d82acabd5b2	2592000	f	900	t	f	03c9b0c7-1b02-4b5b-93ca-d94f5fff38c6	0	f	0	0	0a8a743d-b0e0-4d1e-8747-7513a1e564d1
\.


--
-- Data for Name: realm_attribute; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.realm_attribute (name, realm_id, value) FROM stdin;
_browser_header.contentSecurityPolicyReportOnly	5be18a3e-7181-4862-867b-45aff91b9b87	
_browser_header.xContentTypeOptions	5be18a3e-7181-4862-867b-45aff91b9b87	nosniff
_browser_header.referrerPolicy	5be18a3e-7181-4862-867b-45aff91b9b87	no-referrer
_browser_header.xRobotsTag	5be18a3e-7181-4862-867b-45aff91b9b87	none
_browser_header.xFrameOptions	5be18a3e-7181-4862-867b-45aff91b9b87	SAMEORIGIN
_browser_header.contentSecurityPolicy	5be18a3e-7181-4862-867b-45aff91b9b87	frame-src 'self'; frame-ancestors 'self'; object-src 'none';
_browser_header.xXSSProtection	5be18a3e-7181-4862-867b-45aff91b9b87	1; mode=block
_browser_header.strictTransportSecurity	5be18a3e-7181-4862-867b-45aff91b9b87	max-age=31536000; includeSubDomains
bruteForceProtected	5be18a3e-7181-4862-867b-45aff91b9b87	false
permanentLockout	5be18a3e-7181-4862-867b-45aff91b9b87	false
maxTemporaryLockouts	5be18a3e-7181-4862-867b-45aff91b9b87	0
bruteForceStrategy	5be18a3e-7181-4862-867b-45aff91b9b87	MULTIPLE
maxFailureWaitSeconds	5be18a3e-7181-4862-867b-45aff91b9b87	900
minimumQuickLoginWaitSeconds	5be18a3e-7181-4862-867b-45aff91b9b87	60
waitIncrementSeconds	5be18a3e-7181-4862-867b-45aff91b9b87	60
quickLoginCheckMilliSeconds	5be18a3e-7181-4862-867b-45aff91b9b87	1000
maxDeltaTimeSeconds	5be18a3e-7181-4862-867b-45aff91b9b87	43200
failureFactor	5be18a3e-7181-4862-867b-45aff91b9b87	30
realmReusableOtpCode	5be18a3e-7181-4862-867b-45aff91b9b87	false
firstBrokerLoginFlowId	5be18a3e-7181-4862-867b-45aff91b9b87	3a315df6-567c-4d74-9e76-04a42cb85cdf
displayName	5be18a3e-7181-4862-867b-45aff91b9b87	Keycloak
displayNameHtml	5be18a3e-7181-4862-867b-45aff91b9b87	<div class="kc-logo-text"><span>Keycloak</span></div>
defaultSignatureAlgorithm	5be18a3e-7181-4862-867b-45aff91b9b87	RS256
offlineSessionMaxLifespanEnabled	5be18a3e-7181-4862-867b-45aff91b9b87	false
offlineSessionMaxLifespan	5be18a3e-7181-4862-867b-45aff91b9b87	5184000
_browser_header.contentSecurityPolicyReportOnly	21dfe33f-5923-4bfd-bc04-cf200e747656	
_browser_header.xContentTypeOptions	21dfe33f-5923-4bfd-bc04-cf200e747656	nosniff
_browser_header.referrerPolicy	21dfe33f-5923-4bfd-bc04-cf200e747656	no-referrer
_browser_header.xRobotsTag	21dfe33f-5923-4bfd-bc04-cf200e747656	none
_browser_header.xFrameOptions	21dfe33f-5923-4bfd-bc04-cf200e747656	SAMEORIGIN
_browser_header.contentSecurityPolicy	21dfe33f-5923-4bfd-bc04-cf200e747656	frame-src 'self'; frame-ancestors 'self'; object-src 'none';
_browser_header.xXSSProtection	21dfe33f-5923-4bfd-bc04-cf200e747656	1; mode=block
_browser_header.strictTransportSecurity	21dfe33f-5923-4bfd-bc04-cf200e747656	max-age=31536000; includeSubDomains
bruteForceProtected	21dfe33f-5923-4bfd-bc04-cf200e747656	false
permanentLockout	21dfe33f-5923-4bfd-bc04-cf200e747656	false
maxTemporaryLockouts	21dfe33f-5923-4bfd-bc04-cf200e747656	0
bruteForceStrategy	21dfe33f-5923-4bfd-bc04-cf200e747656	MULTIPLE
maxFailureWaitSeconds	21dfe33f-5923-4bfd-bc04-cf200e747656	900
minimumQuickLoginWaitSeconds	21dfe33f-5923-4bfd-bc04-cf200e747656	60
waitIncrementSeconds	21dfe33f-5923-4bfd-bc04-cf200e747656	60
quickLoginCheckMilliSeconds	21dfe33f-5923-4bfd-bc04-cf200e747656	1000
maxDeltaTimeSeconds	21dfe33f-5923-4bfd-bc04-cf200e747656	43200
failureFactor	21dfe33f-5923-4bfd-bc04-cf200e747656	30
realmReusableOtpCode	21dfe33f-5923-4bfd-bc04-cf200e747656	false
defaultSignatureAlgorithm	21dfe33f-5923-4bfd-bc04-cf200e747656	RS256
offlineSessionMaxLifespanEnabled	21dfe33f-5923-4bfd-bc04-cf200e747656	false
offlineSessionMaxLifespan	21dfe33f-5923-4bfd-bc04-cf200e747656	5184000
actionTokenGeneratedByAdminLifespan	21dfe33f-5923-4bfd-bc04-cf200e747656	43200
actionTokenGeneratedByUserLifespan	21dfe33f-5923-4bfd-bc04-cf200e747656	300
oauth2DeviceCodeLifespan	21dfe33f-5923-4bfd-bc04-cf200e747656	600
oauth2DevicePollingInterval	21dfe33f-5923-4bfd-bc04-cf200e747656	5
webAuthnPolicyRpEntityName	21dfe33f-5923-4bfd-bc04-cf200e747656	keycloak
webAuthnPolicySignatureAlgorithms	21dfe33f-5923-4bfd-bc04-cf200e747656	ES256,RS256
webAuthnPolicyRpId	21dfe33f-5923-4bfd-bc04-cf200e747656	
webAuthnPolicyAttestationConveyancePreference	21dfe33f-5923-4bfd-bc04-cf200e747656	not specified
webAuthnPolicyAuthenticatorAttachment	21dfe33f-5923-4bfd-bc04-cf200e747656	not specified
webAuthnPolicyRequireResidentKey	21dfe33f-5923-4bfd-bc04-cf200e747656	not specified
webAuthnPolicyUserVerificationRequirement	21dfe33f-5923-4bfd-bc04-cf200e747656	not specified
webAuthnPolicyCreateTimeout	21dfe33f-5923-4bfd-bc04-cf200e747656	0
webAuthnPolicyAvoidSameAuthenticatorRegister	21dfe33f-5923-4bfd-bc04-cf200e747656	false
webAuthnPolicyRpEntityNamePasswordless	21dfe33f-5923-4bfd-bc04-cf200e747656	keycloak
webAuthnPolicySignatureAlgorithmsPasswordless	21dfe33f-5923-4bfd-bc04-cf200e747656	ES256,RS256
webAuthnPolicyRpIdPasswordless	21dfe33f-5923-4bfd-bc04-cf200e747656	
webAuthnPolicyAttestationConveyancePreferencePasswordless	21dfe33f-5923-4bfd-bc04-cf200e747656	not specified
webAuthnPolicyAuthenticatorAttachmentPasswordless	21dfe33f-5923-4bfd-bc04-cf200e747656	not specified
webAuthnPolicyRequireResidentKeyPasswordless	21dfe33f-5923-4bfd-bc04-cf200e747656	not specified
webAuthnPolicyUserVerificationRequirementPasswordless	21dfe33f-5923-4bfd-bc04-cf200e747656	not specified
webAuthnPolicyCreateTimeoutPasswordless	21dfe33f-5923-4bfd-bc04-cf200e747656	0
webAuthnPolicyAvoidSameAuthenticatorRegisterPasswordless	21dfe33f-5923-4bfd-bc04-cf200e747656	false
cibaBackchannelTokenDeliveryMode	21dfe33f-5923-4bfd-bc04-cf200e747656	poll
cibaExpiresIn	21dfe33f-5923-4bfd-bc04-cf200e747656	120
cibaInterval	21dfe33f-5923-4bfd-bc04-cf200e747656	5
cibaAuthRequestedUserHint	21dfe33f-5923-4bfd-bc04-cf200e747656	login_hint
parRequestUriLifespan	21dfe33f-5923-4bfd-bc04-cf200e747656	60
firstBrokerLoginFlowId	21dfe33f-5923-4bfd-bc04-cf200e747656	e649748d-6a9d-403a-87c2-8f0c05d06519
\.


--
-- Data for Name: realm_default_groups; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.realm_default_groups (realm_id, group_id) FROM stdin;
\.


--
-- Data for Name: realm_enabled_event_types; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.realm_enabled_event_types (realm_id, value) FROM stdin;
\.


--
-- Data for Name: realm_events_listeners; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.realm_events_listeners (realm_id, value) FROM stdin;
5be18a3e-7181-4862-867b-45aff91b9b87	jboss-logging
21dfe33f-5923-4bfd-bc04-cf200e747656	jboss-logging
\.


--
-- Data for Name: realm_localizations; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.realm_localizations (realm_id, locale, texts) FROM stdin;
\.


--
-- Data for Name: realm_required_credential; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.realm_required_credential (type, form_label, input, secret, realm_id) FROM stdin;
password	password	t	t	5be18a3e-7181-4862-867b-45aff91b9b87
password	password	t	t	21dfe33f-5923-4bfd-bc04-cf200e747656
\.


--
-- Data for Name: realm_smtp_config; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.realm_smtp_config (realm_id, value, name) FROM stdin;
\.


--
-- Data for Name: realm_supported_locales; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.realm_supported_locales (realm_id, value) FROM stdin;
\.


--
-- Data for Name: redirect_uris; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.redirect_uris (client_id, value) FROM stdin;
d0dc1596-18e2-4ccc-bd5e-cc8a1b52db61	/realms/master/account/*
250d1167-7f36-432a-96eb-492124c372b1	/realms/master/account/*
489d25cc-3b6e-49bc-b4d3-7ece35cf3eff	/admin/master/console/*
e1fd0113-c702-4617-9068-7c9142d6b48b	/realms/local/account/*
9f5333a7-931d-4663-b07d-c89928cd6498	/realms/local/account/*
94df3d2f-7a99-4794-92f9-c879ceea36a0	/admin/local/console/*
40f8f713-e1c4-4e9d-a804-2ec22fb3d118	http://localhost:8888/login/oauth2/code/keycloak
ab4df486-dff6-488a-aa26-56cccddaf5fc	http://localhost:8888/*
\.


--
-- Data for Name: required_action_config; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.required_action_config (required_action_id, value, name) FROM stdin;
\.


--
-- Data for Name: required_action_provider; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.required_action_provider (id, alias, name, realm_id, enabled, default_action, provider_id, priority) FROM stdin;
d784d8c4-3620-414a-a57a-b8ccc1cc8e8e	VERIFY_EMAIL	Verify Email	5be18a3e-7181-4862-867b-45aff91b9b87	t	f	VERIFY_EMAIL	50
ff8d037b-21b8-4f82-a26e-35756b32e9bb	UPDATE_PROFILE	Update Profile	5be18a3e-7181-4862-867b-45aff91b9b87	t	f	UPDATE_PROFILE	40
9012d22f-c1ff-4615-9677-65ee47383ce2	CONFIGURE_TOTP	Configure OTP	5be18a3e-7181-4862-867b-45aff91b9b87	t	f	CONFIGURE_TOTP	10
52fde595-3a5a-4566-9b9c-9c813a7adf74	UPDATE_PASSWORD	Update Password	5be18a3e-7181-4862-867b-45aff91b9b87	t	f	UPDATE_PASSWORD	30
58cf0978-e72b-454d-b466-37bc18798afc	TERMS_AND_CONDITIONS	Terms and Conditions	5be18a3e-7181-4862-867b-45aff91b9b87	f	f	TERMS_AND_CONDITIONS	20
63231a56-a87f-441c-8741-bf17b4185b2a	delete_account	Delete Account	5be18a3e-7181-4862-867b-45aff91b9b87	f	f	delete_account	60
241de8a0-e689-4673-aefd-2cddde8024eb	delete_credential	Delete Credential	5be18a3e-7181-4862-867b-45aff91b9b87	t	f	delete_credential	100
6bee417c-9dc3-48f0-b46a-72909b307f91	update_user_locale	Update User Locale	5be18a3e-7181-4862-867b-45aff91b9b87	t	f	update_user_locale	1000
3329572c-ae20-4389-8d70-2f9647cda6ec	webauthn-register	Webauthn Register	5be18a3e-7181-4862-867b-45aff91b9b87	t	f	webauthn-register	70
12582c97-f84a-4cea-b118-15245a0f8339	webauthn-register-passwordless	Webauthn Register Passwordless	5be18a3e-7181-4862-867b-45aff91b9b87	t	f	webauthn-register-passwordless	80
d1a4c999-20df-4632-8c98-a9032b93ab28	VERIFY_PROFILE	Verify Profile	5be18a3e-7181-4862-867b-45aff91b9b87	t	f	VERIFY_PROFILE	90
f1838494-f641-44a6-8c74-1a6e53c6a933	VERIFY_EMAIL	Verify Email	21dfe33f-5923-4bfd-bc04-cf200e747656	t	f	VERIFY_EMAIL	50
1aaff89a-60a7-429f-95c8-6e38e2a2df0e	UPDATE_PROFILE	Update Profile	21dfe33f-5923-4bfd-bc04-cf200e747656	t	f	UPDATE_PROFILE	40
c1bead8b-bf86-4193-b077-75ef53cad4b2	CONFIGURE_TOTP	Configure OTP	21dfe33f-5923-4bfd-bc04-cf200e747656	t	f	CONFIGURE_TOTP	10
a4ce0892-1609-4ba4-ae15-b94a4d16a199	UPDATE_PASSWORD	Update Password	21dfe33f-5923-4bfd-bc04-cf200e747656	t	f	UPDATE_PASSWORD	30
f20559db-fe8f-4818-acb1-ff112944eae8	TERMS_AND_CONDITIONS	Terms and Conditions	21dfe33f-5923-4bfd-bc04-cf200e747656	f	f	TERMS_AND_CONDITIONS	20
2b5e428e-fa7c-4812-a599-fa1878f04b77	delete_account	Delete Account	21dfe33f-5923-4bfd-bc04-cf200e747656	f	f	delete_account	60
48c19e88-a048-47fb-b130-7e4e110ab041	delete_credential	Delete Credential	21dfe33f-5923-4bfd-bc04-cf200e747656	t	f	delete_credential	100
ab84d304-971a-49a8-b97a-02da4e8f6806	update_user_locale	Update User Locale	21dfe33f-5923-4bfd-bc04-cf200e747656	t	f	update_user_locale	1000
68fe688b-3f6c-4e27-9821-d939f29c9d38	webauthn-register	Webauthn Register	21dfe33f-5923-4bfd-bc04-cf200e747656	t	f	webauthn-register	70
c03b8cf5-d50a-4394-99f2-c576140502d7	webauthn-register-passwordless	Webauthn Register Passwordless	21dfe33f-5923-4bfd-bc04-cf200e747656	t	f	webauthn-register-passwordless	80
13c667a9-73e5-406d-8c5a-25dec47f2b24	VERIFY_PROFILE	Verify Profile	21dfe33f-5923-4bfd-bc04-cf200e747656	t	f	VERIFY_PROFILE	90
\.


--
-- Data for Name: resource_attribute; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.resource_attribute (id, name, value, resource_id) FROM stdin;
\.


--
-- Data for Name: resource_policy; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.resource_policy (resource_id, policy_id) FROM stdin;
\.


--
-- Data for Name: resource_scope; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.resource_scope (resource_id, scope_id) FROM stdin;
\.


--
-- Data for Name: resource_server; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.resource_server (id, allow_rs_remote_mgmt, policy_enforce_mode, decision_strategy) FROM stdin;
40f8f713-e1c4-4e9d-a804-2ec22fb3d118	t	0	1
ab4df486-dff6-488a-aa26-56cccddaf5fc	t	0	1
\.


--
-- Data for Name: resource_server_perm_ticket; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.resource_server_perm_ticket (id, owner, requester, created_timestamp, granted_timestamp, resource_id, scope_id, resource_server_id, policy_id) FROM stdin;
\.


--
-- Data for Name: resource_server_policy; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.resource_server_policy (id, name, description, type, decision_strategy, logic, resource_server_id, owner) FROM stdin;
2954b2a2-7a31-4064-918e-6cb0d75cf43a	Default Policy	A policy that grants access only for users within this realm	js	0	0	40f8f713-e1c4-4e9d-a804-2ec22fb3d118	\N
2c907709-c0fa-48bf-bf7a-3e0900464a00	Default Permission	A permission that applies to the default resource type	resource	1	0	40f8f713-e1c4-4e9d-a804-2ec22fb3d118	\N
385360f0-fe21-476f-aa17-6364f7ee537e	Default Policy	A policy that grants access only for users within this realm	js	0	0	ab4df486-dff6-488a-aa26-56cccddaf5fc	\N
f2a0b9fb-9f81-408d-9d85-5179936edbb4	Default Permission	A permission that applies to the default resource type	resource	1	0	ab4df486-dff6-488a-aa26-56cccddaf5fc	\N
\.


--
-- Data for Name: resource_server_resource; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.resource_server_resource (id, name, type, icon_uri, owner, resource_server_id, owner_managed_access, display_name) FROM stdin;
5dbfeb2d-309d-4737-863d-fc6e08027581	Default Resource	urn:local-client:resources:default	\N	40f8f713-e1c4-4e9d-a804-2ec22fb3d118	40f8f713-e1c4-4e9d-a804-2ec22fb3d118	f	\N
3668ca6a-2e4a-411f-98fb-edf0b299ddd3	Default Resource	urn:local-client:resources:default	\N	ab4df486-dff6-488a-aa26-56cccddaf5fc	ab4df486-dff6-488a-aa26-56cccddaf5fc	f	\N
\.


--
-- Data for Name: resource_server_scope; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.resource_server_scope (id, name, icon_uri, resource_server_id, display_name) FROM stdin;
\.


--
-- Data for Name: resource_uris; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.resource_uris (resource_id, value) FROM stdin;
5dbfeb2d-309d-4737-863d-fc6e08027581	/*
3668ca6a-2e4a-411f-98fb-edf0b299ddd3	/*
\.


--
-- Data for Name: revoked_token; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.revoked_token (id, expire) FROM stdin;
\.


--
-- Data for Name: role_attribute; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.role_attribute (id, role_id, name, value) FROM stdin;
\.


--
-- Data for Name: scope_mapping; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.scope_mapping (client_id, role_id) FROM stdin;
250d1167-7f36-432a-96eb-492124c372b1	79d032d2-4b1f-4b01-9418-fa6ad7e29efd
250d1167-7f36-432a-96eb-492124c372b1	32ab400c-b0bc-4231-b184-a9c7ea819c8c
9f5333a7-931d-4663-b07d-c89928cd6498	c2a86f85-7cc1-4205-b98a-42b8557945e1
9f5333a7-931d-4663-b07d-c89928cd6498	58eca8a2-317c-4212-9cbc-e089f3cfb715
\.


--
-- Data for Name: scope_policy; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.scope_policy (scope_id, policy_id) FROM stdin;
\.


--
-- Data for Name: user_attribute; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_attribute (name, value, user_id, id, long_value_hash, long_value_hash_lower_case, long_value) FROM stdin;
is_temporary_admin	true	c3557eb9-249e-4dd9-b72d-9d2977b1af9d	2186d9e8-765a-4e0b-b6db-23fd9a351e1b	\N	\N	\N
\.


--
-- Data for Name: user_consent; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_consent (id, client_id, user_id, created_date, last_updated_date, client_storage_provider, external_client_id) FROM stdin;
\.


--
-- Data for Name: user_consent_client_scope; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_consent_client_scope (user_consent_id, scope_id) FROM stdin;
\.


--
-- Data for Name: user_entity; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_entity (id, email, email_constraint, email_verified, enabled, federation_link, first_name, last_name, realm_id, username, created_timestamp, service_account_client_link, not_before) FROM stdin;
c3557eb9-249e-4dd9-b72d-9d2977b1af9d	\N	92eb8276-880b-494d-b1a1-782d7123e6a6	f	t	\N	\N	\N	5be18a3e-7181-4862-867b-45aff91b9b87	admin	1762546757386	\N	0
dde646db-f964-4728-9ce9-e9552001b16a	lukk@test.com	lukk@test.com	f	t	\N	Lukk	Songo	21dfe33f-5923-4bfd-bc04-cf200e747656	lukk	1762546943766	\N	0
fb55b38b-7f30-48f2-8649-2b0fc95c1295	\N	8f7969b3-739b-4f18-b6e5-26913b574411	f	t	\N	\N	\N	5be18a3e-7181-4862-867b-45aff91b9b87	service-account-local-client	1762554611014	40f8f713-e1c4-4e9d-a804-2ec22fb3d118	0
38964a5c-8032-4ff0-a5ba-37d20178ab25	\N	1f91d15b-c26e-4456-9669-d156beb42efd	f	t	\N	\N	\N	21dfe33f-5923-4bfd-bc04-cf200e747656	service-account-local-client	1762558445164	ab4df486-dff6-488a-aa26-56cccddaf5fc	0
\.


--
-- Data for Name: user_federation_config; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_federation_config (user_federation_provider_id, value, name) FROM stdin;
\.


--
-- Data for Name: user_federation_mapper; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_federation_mapper (id, name, federation_provider_id, federation_mapper_type, realm_id) FROM stdin;
\.


--
-- Data for Name: user_federation_mapper_config; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_federation_mapper_config (user_federation_mapper_id, value, name) FROM stdin;
\.


--
-- Data for Name: user_federation_provider; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_federation_provider (id, changed_sync_period, display_name, full_sync_period, last_sync, priority, provider_name, realm_id) FROM stdin;
\.


--
-- Data for Name: user_group_membership; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_group_membership (group_id, user_id, membership_type) FROM stdin;
\.


--
-- Data for Name: user_required_action; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_required_action (user_id, required_action) FROM stdin;
\.


--
-- Data for Name: user_role_mapping; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_role_mapping (role_id, user_id) FROM stdin;
88007421-49af-4531-9b09-3025a88deb0f	c3557eb9-249e-4dd9-b72d-9d2977b1af9d
e7ecdf7c-50e6-4c10-b17f-8075d29c107c	c3557eb9-249e-4dd9-b72d-9d2977b1af9d
0a8a743d-b0e0-4d1e-8747-7513a1e564d1	dde646db-f964-4728-9ce9-e9552001b16a
70f6f49a-2ad3-43ed-a6f1-8687b61f5b66	dde646db-f964-4728-9ce9-e9552001b16a
88007421-49af-4531-9b09-3025a88deb0f	fb55b38b-7f30-48f2-8649-2b0fc95c1295
5db3f6d8-31ea-4ea8-af29-e8e2f244bf73	fb55b38b-7f30-48f2-8649-2b0fc95c1295
0a8a743d-b0e0-4d1e-8747-7513a1e564d1	38964a5c-8032-4ff0-a5ba-37d20178ab25
7581451c-4ff2-4d0a-8402-14d22578ba17	38964a5c-8032-4ff0-a5ba-37d20178ab25
\.


--
-- Data for Name: username_login_failure; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.username_login_failure (realm_id, username, failed_login_not_before, last_failure, last_ip_failure, num_failures) FROM stdin;
\.


--
-- Data for Name: web_origins; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.web_origins (client_id, value) FROM stdin;
489d25cc-3b6e-49bc-b4d3-7ece35cf3eff	+
94df3d2f-7a99-4794-92f9-c879ceea36a0	+
40f8f713-e1c4-4e9d-a804-2ec22fb3d118	http://localhost:8888
ab4df486-dff6-488a-aa26-56cccddaf5fc	http://localhost:8888
\.


--
-- Name: username_login_failure CONSTRAINT_17-2; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.username_login_failure
    ADD CONSTRAINT "CONSTRAINT_17-2" PRIMARY KEY (realm_id, username);


--
-- Name: org_domain ORG_DOMAIN_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.org_domain
    ADD CONSTRAINT "ORG_DOMAIN_pkey" PRIMARY KEY (id, name);


--
-- Name: org ORG_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.org
    ADD CONSTRAINT "ORG_pkey" PRIMARY KEY (id);


--
-- Name: keycloak_role UK_J3RWUVD56ONTGSUHOGM184WW2-2; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.keycloak_role
    ADD CONSTRAINT "UK_J3RWUVD56ONTGSUHOGM184WW2-2" UNIQUE (name, client_realm_constraint);


--
-- Name: client_auth_flow_bindings c_cli_flow_bind; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.client_auth_flow_bindings
    ADD CONSTRAINT c_cli_flow_bind PRIMARY KEY (client_id, binding_name);


--
-- Name: client_scope_client c_cli_scope_bind; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.client_scope_client
    ADD CONSTRAINT c_cli_scope_bind PRIMARY KEY (client_id, scope_id);


--
-- Name: client_initial_access cnstr_client_init_acc_pk; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.client_initial_access
    ADD CONSTRAINT cnstr_client_init_acc_pk PRIMARY KEY (id);


--
-- Name: realm_default_groups con_group_id_def_groups; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.realm_default_groups
    ADD CONSTRAINT con_group_id_def_groups UNIQUE (group_id);


--
-- Name: broker_link constr_broker_link_pk; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.broker_link
    ADD CONSTRAINT constr_broker_link_pk PRIMARY KEY (identity_provider, user_id);


--
-- Name: component_config constr_component_config_pk; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.component_config
    ADD CONSTRAINT constr_component_config_pk PRIMARY KEY (id);


--
-- Name: component constr_component_pk; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.component
    ADD CONSTRAINT constr_component_pk PRIMARY KEY (id);


--
-- Name: fed_user_required_action constr_fed_required_action; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fed_user_required_action
    ADD CONSTRAINT constr_fed_required_action PRIMARY KEY (required_action, user_id);


--
-- Name: fed_user_attribute constr_fed_user_attr_pk; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fed_user_attribute
    ADD CONSTRAINT constr_fed_user_attr_pk PRIMARY KEY (id);


--
-- Name: fed_user_consent constr_fed_user_consent_pk; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fed_user_consent
    ADD CONSTRAINT constr_fed_user_consent_pk PRIMARY KEY (id);


--
-- Name: fed_user_credential constr_fed_user_cred_pk; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fed_user_credential
    ADD CONSTRAINT constr_fed_user_cred_pk PRIMARY KEY (id);


--
-- Name: fed_user_group_membership constr_fed_user_group; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fed_user_group_membership
    ADD CONSTRAINT constr_fed_user_group PRIMARY KEY (group_id, user_id);


--
-- Name: fed_user_role_mapping constr_fed_user_role; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fed_user_role_mapping
    ADD CONSTRAINT constr_fed_user_role PRIMARY KEY (role_id, user_id);


--
-- Name: federated_user constr_federated_user; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.federated_user
    ADD CONSTRAINT constr_federated_user PRIMARY KEY (id);


--
-- Name: realm_default_groups constr_realm_default_groups; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.realm_default_groups
    ADD CONSTRAINT constr_realm_default_groups PRIMARY KEY (realm_id, group_id);


--
-- Name: realm_enabled_event_types constr_realm_enabl_event_types; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.realm_enabled_event_types
    ADD CONSTRAINT constr_realm_enabl_event_types PRIMARY KEY (realm_id, value);


--
-- Name: realm_events_listeners constr_realm_events_listeners; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.realm_events_listeners
    ADD CONSTRAINT constr_realm_events_listeners PRIMARY KEY (realm_id, value);


--
-- Name: realm_supported_locales constr_realm_supported_locales; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.realm_supported_locales
    ADD CONSTRAINT constr_realm_supported_locales PRIMARY KEY (realm_id, value);


--
-- Name: identity_provider constraint_2b; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.identity_provider
    ADD CONSTRAINT constraint_2b PRIMARY KEY (internal_id);


--
-- Name: client_attributes constraint_3c; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.client_attributes
    ADD CONSTRAINT constraint_3c PRIMARY KEY (client_id, name);


--
-- Name: event_entity constraint_4; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.event_entity
    ADD CONSTRAINT constraint_4 PRIMARY KEY (id);


--
-- Name: federated_identity constraint_40; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.federated_identity
    ADD CONSTRAINT constraint_40 PRIMARY KEY (identity_provider, user_id);


--
-- Name: realm constraint_4a; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.realm
    ADD CONSTRAINT constraint_4a PRIMARY KEY (id);


--
-- Name: user_federation_provider constraint_5c; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_federation_provider
    ADD CONSTRAINT constraint_5c PRIMARY KEY (id);


--
-- Name: client constraint_7; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.client
    ADD CONSTRAINT constraint_7 PRIMARY KEY (id);


--
-- Name: scope_mapping constraint_81; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scope_mapping
    ADD CONSTRAINT constraint_81 PRIMARY KEY (client_id, role_id);


--
-- Name: client_node_registrations constraint_84; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.client_node_registrations
    ADD CONSTRAINT constraint_84 PRIMARY KEY (client_id, name);


--
-- Name: realm_attribute constraint_9; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.realm_attribute
    ADD CONSTRAINT constraint_9 PRIMARY KEY (name, realm_id);


--
-- Name: realm_required_credential constraint_92; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.realm_required_credential
    ADD CONSTRAINT constraint_92 PRIMARY KEY (realm_id, type);


--
-- Name: keycloak_role constraint_a; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.keycloak_role
    ADD CONSTRAINT constraint_a PRIMARY KEY (id);


--
-- Name: admin_event_entity constraint_admin_event_entity; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.admin_event_entity
    ADD CONSTRAINT constraint_admin_event_entity PRIMARY KEY (id);


--
-- Name: authenticator_config_entry constraint_auth_cfg_pk; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.authenticator_config_entry
    ADD CONSTRAINT constraint_auth_cfg_pk PRIMARY KEY (authenticator_id, name);


--
-- Name: authentication_execution constraint_auth_exec_pk; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.authentication_execution
    ADD CONSTRAINT constraint_auth_exec_pk PRIMARY KEY (id);


--
-- Name: authentication_flow constraint_auth_flow_pk; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.authentication_flow
    ADD CONSTRAINT constraint_auth_flow_pk PRIMARY KEY (id);


--
-- Name: authenticator_config constraint_auth_pk; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.authenticator_config
    ADD CONSTRAINT constraint_auth_pk PRIMARY KEY (id);


--
-- Name: user_role_mapping constraint_c; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_role_mapping
    ADD CONSTRAINT constraint_c PRIMARY KEY (role_id, user_id);


--
-- Name: composite_role constraint_composite_role; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.composite_role
    ADD CONSTRAINT constraint_composite_role PRIMARY KEY (composite, child_role);


--
-- Name: identity_provider_config constraint_d; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.identity_provider_config
    ADD CONSTRAINT constraint_d PRIMARY KEY (identity_provider_id, name);


--
-- Name: policy_config constraint_dpc; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.policy_config
    ADD CONSTRAINT constraint_dpc PRIMARY KEY (policy_id, name);


--
-- Name: realm_smtp_config constraint_e; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.realm_smtp_config
    ADD CONSTRAINT constraint_e PRIMARY KEY (realm_id, name);


--
-- Name: credential constraint_f; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.credential
    ADD CONSTRAINT constraint_f PRIMARY KEY (id);


--
-- Name: user_federation_config constraint_f9; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_federation_config
    ADD CONSTRAINT constraint_f9 PRIMARY KEY (user_federation_provider_id, name);


--
-- Name: resource_server_perm_ticket constraint_fapmt; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.resource_server_perm_ticket
    ADD CONSTRAINT constraint_fapmt PRIMARY KEY (id);


--
-- Name: resource_server_resource constraint_farsr; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.resource_server_resource
    ADD CONSTRAINT constraint_farsr PRIMARY KEY (id);


--
-- Name: resource_server_policy constraint_farsrp; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.resource_server_policy
    ADD CONSTRAINT constraint_farsrp PRIMARY KEY (id);


--
-- Name: associated_policy constraint_farsrpap; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.associated_policy
    ADD CONSTRAINT constraint_farsrpap PRIMARY KEY (policy_id, associated_policy_id);


--
-- Name: resource_policy constraint_farsrpp; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.resource_policy
    ADD CONSTRAINT constraint_farsrpp PRIMARY KEY (resource_id, policy_id);


--
-- Name: resource_server_scope constraint_farsrs; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.resource_server_scope
    ADD CONSTRAINT constraint_farsrs PRIMARY KEY (id);


--
-- Name: resource_scope constraint_farsrsp; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.resource_scope
    ADD CONSTRAINT constraint_farsrsp PRIMARY KEY (resource_id, scope_id);


--
-- Name: scope_policy constraint_farsrsps; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scope_policy
    ADD CONSTRAINT constraint_farsrsps PRIMARY KEY (scope_id, policy_id);


--
-- Name: user_entity constraint_fb; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_entity
    ADD CONSTRAINT constraint_fb PRIMARY KEY (id);


--
-- Name: user_federation_mapper_config constraint_fedmapper_cfg_pm; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_federation_mapper_config
    ADD CONSTRAINT constraint_fedmapper_cfg_pm PRIMARY KEY (user_federation_mapper_id, name);


--
-- Name: user_federation_mapper constraint_fedmapperpm; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_federation_mapper
    ADD CONSTRAINT constraint_fedmapperpm PRIMARY KEY (id);


--
-- Name: fed_user_consent_cl_scope constraint_fgrntcsnt_clsc_pm; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fed_user_consent_cl_scope
    ADD CONSTRAINT constraint_fgrntcsnt_clsc_pm PRIMARY KEY (user_consent_id, scope_id);


--
-- Name: user_consent_client_scope constraint_grntcsnt_clsc_pm; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_consent_client_scope
    ADD CONSTRAINT constraint_grntcsnt_clsc_pm PRIMARY KEY (user_consent_id, scope_id);


--
-- Name: user_consent constraint_grntcsnt_pm; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_consent
    ADD CONSTRAINT constraint_grntcsnt_pm PRIMARY KEY (id);


--
-- Name: keycloak_group constraint_group; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.keycloak_group
    ADD CONSTRAINT constraint_group PRIMARY KEY (id);


--
-- Name: group_attribute constraint_group_attribute_pk; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.group_attribute
    ADD CONSTRAINT constraint_group_attribute_pk PRIMARY KEY (id);


--
-- Name: group_role_mapping constraint_group_role; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.group_role_mapping
    ADD CONSTRAINT constraint_group_role PRIMARY KEY (role_id, group_id);


--
-- Name: identity_provider_mapper constraint_idpm; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.identity_provider_mapper
    ADD CONSTRAINT constraint_idpm PRIMARY KEY (id);


--
-- Name: idp_mapper_config constraint_idpmconfig; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.idp_mapper_config
    ADD CONSTRAINT constraint_idpmconfig PRIMARY KEY (idp_mapper_id, name);


--
-- Name: migration_model constraint_migmod; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.migration_model
    ADD CONSTRAINT constraint_migmod PRIMARY KEY (id);


--
-- Name: offline_client_session constraint_offl_cl_ses_pk3; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.offline_client_session
    ADD CONSTRAINT constraint_offl_cl_ses_pk3 PRIMARY KEY (user_session_id, client_id, client_storage_provider, external_client_id, offline_flag);


--
-- Name: offline_user_session constraint_offl_us_ses_pk2; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.offline_user_session
    ADD CONSTRAINT constraint_offl_us_ses_pk2 PRIMARY KEY (user_session_id, offline_flag);


--
-- Name: protocol_mapper constraint_pcm; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.protocol_mapper
    ADD CONSTRAINT constraint_pcm PRIMARY KEY (id);


--
-- Name: protocol_mapper_config constraint_pmconfig; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.protocol_mapper_config
    ADD CONSTRAINT constraint_pmconfig PRIMARY KEY (protocol_mapper_id, name);


--
-- Name: redirect_uris constraint_redirect_uris; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.redirect_uris
    ADD CONSTRAINT constraint_redirect_uris PRIMARY KEY (client_id, value);


--
-- Name: required_action_config constraint_req_act_cfg_pk; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.required_action_config
    ADD CONSTRAINT constraint_req_act_cfg_pk PRIMARY KEY (required_action_id, name);


--
-- Name: required_action_provider constraint_req_act_prv_pk; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.required_action_provider
    ADD CONSTRAINT constraint_req_act_prv_pk PRIMARY KEY (id);


--
-- Name: user_required_action constraint_required_action; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_required_action
    ADD CONSTRAINT constraint_required_action PRIMARY KEY (required_action, user_id);


--
-- Name: resource_uris constraint_resour_uris_pk; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.resource_uris
    ADD CONSTRAINT constraint_resour_uris_pk PRIMARY KEY (resource_id, value);


--
-- Name: role_attribute constraint_role_attribute_pk; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.role_attribute
    ADD CONSTRAINT constraint_role_attribute_pk PRIMARY KEY (id);


--
-- Name: revoked_token constraint_rt; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.revoked_token
    ADD CONSTRAINT constraint_rt PRIMARY KEY (id);


--
-- Name: user_attribute constraint_user_attribute_pk; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_attribute
    ADD CONSTRAINT constraint_user_attribute_pk PRIMARY KEY (id);


--
-- Name: user_group_membership constraint_user_group; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_group_membership
    ADD CONSTRAINT constraint_user_group PRIMARY KEY (group_id, user_id);


--
-- Name: web_origins constraint_web_origins; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.web_origins
    ADD CONSTRAINT constraint_web_origins PRIMARY KEY (client_id, value);


--
-- Name: databasechangeloglock databasechangeloglock_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.databasechangeloglock
    ADD CONSTRAINT databasechangeloglock_pkey PRIMARY KEY (id);


--
-- Name: client_scope_attributes pk_cl_tmpl_attr; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.client_scope_attributes
    ADD CONSTRAINT pk_cl_tmpl_attr PRIMARY KEY (scope_id, name);


--
-- Name: client_scope pk_cli_template; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.client_scope
    ADD CONSTRAINT pk_cli_template PRIMARY KEY (id);


--
-- Name: resource_server pk_resource_server; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.resource_server
    ADD CONSTRAINT pk_resource_server PRIMARY KEY (id);


--
-- Name: client_scope_role_mapping pk_template_scope; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.client_scope_role_mapping
    ADD CONSTRAINT pk_template_scope PRIMARY KEY (scope_id, role_id);


--
-- Name: default_client_scope r_def_cli_scope_bind; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.default_client_scope
    ADD CONSTRAINT r_def_cli_scope_bind PRIMARY KEY (realm_id, scope_id);


--
-- Name: realm_localizations realm_localizations_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.realm_localizations
    ADD CONSTRAINT realm_localizations_pkey PRIMARY KEY (realm_id, locale);


--
-- Name: resource_attribute res_attr_pk; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.resource_attribute
    ADD CONSTRAINT res_attr_pk PRIMARY KEY (id);


--
-- Name: keycloak_group sibling_names; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.keycloak_group
    ADD CONSTRAINT sibling_names UNIQUE (realm_id, parent_group, name);


--
-- Name: identity_provider uk_2daelwnibji49avxsrtuf6xj33; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.identity_provider
    ADD CONSTRAINT uk_2daelwnibji49avxsrtuf6xj33 UNIQUE (provider_alias, realm_id);


--
-- Name: client uk_b71cjlbenv945rb6gcon438at; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.client
    ADD CONSTRAINT uk_b71cjlbenv945rb6gcon438at UNIQUE (realm_id, client_id);


--
-- Name: client_scope uk_cli_scope; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.client_scope
    ADD CONSTRAINT uk_cli_scope UNIQUE (realm_id, name);


--
-- Name: user_entity uk_dykn684sl8up1crfei6eckhd7; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_entity
    ADD CONSTRAINT uk_dykn684sl8up1crfei6eckhd7 UNIQUE (realm_id, email_constraint);


--
-- Name: user_consent uk_external_consent; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_consent
    ADD CONSTRAINT uk_external_consent UNIQUE (client_storage_provider, external_client_id, user_id);


--
-- Name: resource_server_resource uk_frsr6t700s9v50bu18ws5ha6; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.resource_server_resource
    ADD CONSTRAINT uk_frsr6t700s9v50bu18ws5ha6 UNIQUE (name, owner, resource_server_id);


--
-- Name: resource_server_perm_ticket uk_frsr6t700s9v50bu18ws5pmt; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.resource_server_perm_ticket
    ADD CONSTRAINT uk_frsr6t700s9v50bu18ws5pmt UNIQUE (owner, requester, resource_server_id, resource_id, scope_id);


--
-- Name: resource_server_policy uk_frsrpt700s9v50bu18ws5ha6; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.resource_server_policy
    ADD CONSTRAINT uk_frsrpt700s9v50bu18ws5ha6 UNIQUE (name, resource_server_id);


--
-- Name: resource_server_scope uk_frsrst700s9v50bu18ws5ha6; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.resource_server_scope
    ADD CONSTRAINT uk_frsrst700s9v50bu18ws5ha6 UNIQUE (name, resource_server_id);


--
-- Name: user_consent uk_local_consent; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_consent
    ADD CONSTRAINT uk_local_consent UNIQUE (client_id, user_id);


--
-- Name: org uk_org_alias; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.org
    ADD CONSTRAINT uk_org_alias UNIQUE (realm_id, alias);


--
-- Name: org uk_org_group; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.org
    ADD CONSTRAINT uk_org_group UNIQUE (group_id);


--
-- Name: org uk_org_name; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.org
    ADD CONSTRAINT uk_org_name UNIQUE (realm_id, name);


--
-- Name: realm uk_orvsdmla56612eaefiq6wl5oi; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.realm
    ADD CONSTRAINT uk_orvsdmla56612eaefiq6wl5oi UNIQUE (name);


--
-- Name: user_entity uk_ru8tt6t700s9v50bu18ws5ha6; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_entity
    ADD CONSTRAINT uk_ru8tt6t700s9v50bu18ws5ha6 UNIQUE (realm_id, username);


--
-- Name: fed_user_attr_long_values; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fed_user_attr_long_values ON public.fed_user_attribute USING btree (long_value_hash, name);


--
-- Name: fed_user_attr_long_values_lower_case; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fed_user_attr_long_values_lower_case ON public.fed_user_attribute USING btree (long_value_hash_lower_case, name);


--
-- Name: idx_admin_event_time; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_admin_event_time ON public.admin_event_entity USING btree (realm_id, admin_event_time);


--
-- Name: idx_assoc_pol_assoc_pol_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_assoc_pol_assoc_pol_id ON public.associated_policy USING btree (associated_policy_id);


--
-- Name: idx_auth_config_realm; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_auth_config_realm ON public.authenticator_config USING btree (realm_id);


--
-- Name: idx_auth_exec_flow; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_auth_exec_flow ON public.authentication_execution USING btree (flow_id);


--
-- Name: idx_auth_exec_realm_flow; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_auth_exec_realm_flow ON public.authentication_execution USING btree (realm_id, flow_id);


--
-- Name: idx_auth_flow_realm; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_auth_flow_realm ON public.authentication_flow USING btree (realm_id);


--
-- Name: idx_cl_clscope; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_cl_clscope ON public.client_scope_client USING btree (scope_id);


--
-- Name: idx_client_att_by_name_value; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_client_att_by_name_value ON public.client_attributes USING btree (name, substr(value, 1, 255));


--
-- Name: idx_client_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_client_id ON public.client USING btree (client_id);


--
-- Name: idx_client_init_acc_realm; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_client_init_acc_realm ON public.client_initial_access USING btree (realm_id);


--
-- Name: idx_clscope_attrs; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_clscope_attrs ON public.client_scope_attributes USING btree (scope_id);


--
-- Name: idx_clscope_cl; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_clscope_cl ON public.client_scope_client USING btree (client_id);


--
-- Name: idx_clscope_protmap; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_clscope_protmap ON public.protocol_mapper USING btree (client_scope_id);


--
-- Name: idx_clscope_role; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_clscope_role ON public.client_scope_role_mapping USING btree (scope_id);


--
-- Name: idx_compo_config_compo; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_compo_config_compo ON public.component_config USING btree (component_id);


--
-- Name: idx_component_provider_type; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_component_provider_type ON public.component USING btree (provider_type);


--
-- Name: idx_component_realm; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_component_realm ON public.component USING btree (realm_id);


--
-- Name: idx_composite; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_composite ON public.composite_role USING btree (composite);


--
-- Name: idx_composite_child; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_composite_child ON public.composite_role USING btree (child_role);


--
-- Name: idx_defcls_realm; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_defcls_realm ON public.default_client_scope USING btree (realm_id);


--
-- Name: idx_defcls_scope; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_defcls_scope ON public.default_client_scope USING btree (scope_id);


--
-- Name: idx_event_time; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_event_time ON public.event_entity USING btree (realm_id, event_time);


--
-- Name: idx_fedidentity_feduser; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_fedidentity_feduser ON public.federated_identity USING btree (federated_user_id);


--
-- Name: idx_fedidentity_user; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_fedidentity_user ON public.federated_identity USING btree (user_id);


--
-- Name: idx_fu_attribute; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_fu_attribute ON public.fed_user_attribute USING btree (user_id, realm_id, name);


--
-- Name: idx_fu_cnsnt_ext; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_fu_cnsnt_ext ON public.fed_user_consent USING btree (user_id, client_storage_provider, external_client_id);


--
-- Name: idx_fu_consent; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_fu_consent ON public.fed_user_consent USING btree (user_id, client_id);


--
-- Name: idx_fu_consent_ru; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_fu_consent_ru ON public.fed_user_consent USING btree (realm_id, user_id);


--
-- Name: idx_fu_credential; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_fu_credential ON public.fed_user_credential USING btree (user_id, type);


--
-- Name: idx_fu_credential_ru; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_fu_credential_ru ON public.fed_user_credential USING btree (realm_id, user_id);


--
-- Name: idx_fu_group_membership; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_fu_group_membership ON public.fed_user_group_membership USING btree (user_id, group_id);


--
-- Name: idx_fu_group_membership_ru; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_fu_group_membership_ru ON public.fed_user_group_membership USING btree (realm_id, user_id);


--
-- Name: idx_fu_required_action; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_fu_required_action ON public.fed_user_required_action USING btree (user_id, required_action);


--
-- Name: idx_fu_required_action_ru; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_fu_required_action_ru ON public.fed_user_required_action USING btree (realm_id, user_id);


--
-- Name: idx_fu_role_mapping; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_fu_role_mapping ON public.fed_user_role_mapping USING btree (user_id, role_id);


--
-- Name: idx_fu_role_mapping_ru; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_fu_role_mapping_ru ON public.fed_user_role_mapping USING btree (realm_id, user_id);


--
-- Name: idx_group_att_by_name_value; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_group_att_by_name_value ON public.group_attribute USING btree (name, ((value)::character varying(250)));


--
-- Name: idx_group_attr_group; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_group_attr_group ON public.group_attribute USING btree (group_id);


--
-- Name: idx_group_role_mapp_group; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_group_role_mapp_group ON public.group_role_mapping USING btree (group_id);


--
-- Name: idx_id_prov_mapp_realm; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_id_prov_mapp_realm ON public.identity_provider_mapper USING btree (realm_id);


--
-- Name: idx_ident_prov_realm; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_ident_prov_realm ON public.identity_provider USING btree (realm_id);


--
-- Name: idx_idp_for_login; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_idp_for_login ON public.identity_provider USING btree (realm_id, enabled, link_only, hide_on_login, organization_id);


--
-- Name: idx_idp_realm_org; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_idp_realm_org ON public.identity_provider USING btree (realm_id, organization_id);


--
-- Name: idx_keycloak_role_client; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_keycloak_role_client ON public.keycloak_role USING btree (client);


--
-- Name: idx_keycloak_role_realm; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_keycloak_role_realm ON public.keycloak_role USING btree (realm);


--
-- Name: idx_offline_uss_by_broker_session_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_offline_uss_by_broker_session_id ON public.offline_user_session USING btree (broker_session_id, realm_id);


--
-- Name: idx_offline_uss_by_last_session_refresh; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_offline_uss_by_last_session_refresh ON public.offline_user_session USING btree (realm_id, offline_flag, last_session_refresh);


--
-- Name: idx_offline_uss_by_user; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_offline_uss_by_user ON public.offline_user_session USING btree (user_id, realm_id, offline_flag);


--
-- Name: idx_org_domain_org_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_org_domain_org_id ON public.org_domain USING btree (org_id);


--
-- Name: idx_perm_ticket_owner; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_perm_ticket_owner ON public.resource_server_perm_ticket USING btree (owner);


--
-- Name: idx_perm_ticket_requester; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_perm_ticket_requester ON public.resource_server_perm_ticket USING btree (requester);


--
-- Name: idx_protocol_mapper_client; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_protocol_mapper_client ON public.protocol_mapper USING btree (client_id);


--
-- Name: idx_realm_attr_realm; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_realm_attr_realm ON public.realm_attribute USING btree (realm_id);


--
-- Name: idx_realm_clscope; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_realm_clscope ON public.client_scope USING btree (realm_id);


--
-- Name: idx_realm_def_grp_realm; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_realm_def_grp_realm ON public.realm_default_groups USING btree (realm_id);


--
-- Name: idx_realm_evt_list_realm; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_realm_evt_list_realm ON public.realm_events_listeners USING btree (realm_id);


--
-- Name: idx_realm_evt_types_realm; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_realm_evt_types_realm ON public.realm_enabled_event_types USING btree (realm_id);


--
-- Name: idx_realm_master_adm_cli; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_realm_master_adm_cli ON public.realm USING btree (master_admin_client);


--
-- Name: idx_realm_supp_local_realm; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_realm_supp_local_realm ON public.realm_supported_locales USING btree (realm_id);


--
-- Name: idx_redir_uri_client; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_redir_uri_client ON public.redirect_uris USING btree (client_id);


--
-- Name: idx_req_act_prov_realm; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_req_act_prov_realm ON public.required_action_provider USING btree (realm_id);


--
-- Name: idx_res_policy_policy; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_res_policy_policy ON public.resource_policy USING btree (policy_id);


--
-- Name: idx_res_scope_scope; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_res_scope_scope ON public.resource_scope USING btree (scope_id);


--
-- Name: idx_res_serv_pol_res_serv; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_res_serv_pol_res_serv ON public.resource_server_policy USING btree (resource_server_id);


--
-- Name: idx_res_srv_res_res_srv; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_res_srv_res_res_srv ON public.resource_server_resource USING btree (resource_server_id);


--
-- Name: idx_res_srv_scope_res_srv; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_res_srv_scope_res_srv ON public.resource_server_scope USING btree (resource_server_id);


--
-- Name: idx_rev_token_on_expire; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_rev_token_on_expire ON public.revoked_token USING btree (expire);


--
-- Name: idx_role_attribute; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_role_attribute ON public.role_attribute USING btree (role_id);


--
-- Name: idx_role_clscope; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_role_clscope ON public.client_scope_role_mapping USING btree (role_id);


--
-- Name: idx_scope_mapping_role; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_scope_mapping_role ON public.scope_mapping USING btree (role_id);


--
-- Name: idx_scope_policy_policy; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_scope_policy_policy ON public.scope_policy USING btree (policy_id);


--
-- Name: idx_update_time; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_update_time ON public.migration_model USING btree (update_time);


--
-- Name: idx_usconsent_clscope; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_usconsent_clscope ON public.user_consent_client_scope USING btree (user_consent_id);


--
-- Name: idx_usconsent_scope_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_usconsent_scope_id ON public.user_consent_client_scope USING btree (scope_id);


--
-- Name: idx_user_attribute; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_user_attribute ON public.user_attribute USING btree (user_id);


--
-- Name: idx_user_attribute_name; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_user_attribute_name ON public.user_attribute USING btree (name, value);


--
-- Name: idx_user_consent; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_user_consent ON public.user_consent USING btree (user_id);


--
-- Name: idx_user_credential; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_user_credential ON public.credential USING btree (user_id);


--
-- Name: idx_user_email; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_user_email ON public.user_entity USING btree (email);


--
-- Name: idx_user_group_mapping; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_user_group_mapping ON public.user_group_membership USING btree (user_id);


--
-- Name: idx_user_reqactions; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_user_reqactions ON public.user_required_action USING btree (user_id);


--
-- Name: idx_user_role_mapping; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_user_role_mapping ON public.user_role_mapping USING btree (user_id);


--
-- Name: idx_user_service_account; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_user_service_account ON public.user_entity USING btree (realm_id, service_account_client_link);


--
-- Name: idx_usr_fed_map_fed_prv; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_usr_fed_map_fed_prv ON public.user_federation_mapper USING btree (federation_provider_id);


--
-- Name: idx_usr_fed_map_realm; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_usr_fed_map_realm ON public.user_federation_mapper USING btree (realm_id);


--
-- Name: idx_usr_fed_prv_realm; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_usr_fed_prv_realm ON public.user_federation_provider USING btree (realm_id);


--
-- Name: idx_web_orig_client; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_web_orig_client ON public.web_origins USING btree (client_id);


--
-- Name: user_attr_long_values; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX user_attr_long_values ON public.user_attribute USING btree (long_value_hash, name);


--
-- Name: user_attr_long_values_lower_case; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX user_attr_long_values_lower_case ON public.user_attribute USING btree (long_value_hash_lower_case, name);


--
-- Name: identity_provider fk2b4ebc52ae5c3b34; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.identity_provider
    ADD CONSTRAINT fk2b4ebc52ae5c3b34 FOREIGN KEY (realm_id) REFERENCES public.realm(id);


--
-- Name: client_attributes fk3c47c64beacca966; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.client_attributes
    ADD CONSTRAINT fk3c47c64beacca966 FOREIGN KEY (client_id) REFERENCES public.client(id);


--
-- Name: federated_identity fk404288b92ef007a6; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.federated_identity
    ADD CONSTRAINT fk404288b92ef007a6 FOREIGN KEY (user_id) REFERENCES public.user_entity(id);


--
-- Name: client_node_registrations fk4129723ba992f594; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.client_node_registrations
    ADD CONSTRAINT fk4129723ba992f594 FOREIGN KEY (client_id) REFERENCES public.client(id);


--
-- Name: redirect_uris fk_1burs8pb4ouj97h5wuppahv9f; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.redirect_uris
    ADD CONSTRAINT fk_1burs8pb4ouj97h5wuppahv9f FOREIGN KEY (client_id) REFERENCES public.client(id);


--
-- Name: user_federation_provider fk_1fj32f6ptolw2qy60cd8n01e8; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_federation_provider
    ADD CONSTRAINT fk_1fj32f6ptolw2qy60cd8n01e8 FOREIGN KEY (realm_id) REFERENCES public.realm(id);


--
-- Name: realm_required_credential fk_5hg65lybevavkqfki3kponh9v; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.realm_required_credential
    ADD CONSTRAINT fk_5hg65lybevavkqfki3kponh9v FOREIGN KEY (realm_id) REFERENCES public.realm(id);


--
-- Name: resource_attribute fk_5hrm2vlf9ql5fu022kqepovbr; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.resource_attribute
    ADD CONSTRAINT fk_5hrm2vlf9ql5fu022kqepovbr FOREIGN KEY (resource_id) REFERENCES public.resource_server_resource(id);


--
-- Name: user_attribute fk_5hrm2vlf9ql5fu043kqepovbr; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_attribute
    ADD CONSTRAINT fk_5hrm2vlf9ql5fu043kqepovbr FOREIGN KEY (user_id) REFERENCES public.user_entity(id);


--
-- Name: user_required_action fk_6qj3w1jw9cvafhe19bwsiuvmd; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_required_action
    ADD CONSTRAINT fk_6qj3w1jw9cvafhe19bwsiuvmd FOREIGN KEY (user_id) REFERENCES public.user_entity(id);


--
-- Name: keycloak_role fk_6vyqfe4cn4wlq8r6kt5vdsj5c; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.keycloak_role
    ADD CONSTRAINT fk_6vyqfe4cn4wlq8r6kt5vdsj5c FOREIGN KEY (realm) REFERENCES public.realm(id);


--
-- Name: realm_smtp_config fk_70ej8xdxgxd0b9hh6180irr0o; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.realm_smtp_config
    ADD CONSTRAINT fk_70ej8xdxgxd0b9hh6180irr0o FOREIGN KEY (realm_id) REFERENCES public.realm(id);


--
-- Name: realm_attribute fk_8shxd6l3e9atqukacxgpffptw; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.realm_attribute
    ADD CONSTRAINT fk_8shxd6l3e9atqukacxgpffptw FOREIGN KEY (realm_id) REFERENCES public.realm(id);


--
-- Name: composite_role fk_a63wvekftu8jo1pnj81e7mce2; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.composite_role
    ADD CONSTRAINT fk_a63wvekftu8jo1pnj81e7mce2 FOREIGN KEY (composite) REFERENCES public.keycloak_role(id);


--
-- Name: authentication_execution fk_auth_exec_flow; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.authentication_execution
    ADD CONSTRAINT fk_auth_exec_flow FOREIGN KEY (flow_id) REFERENCES public.authentication_flow(id);


--
-- Name: authentication_execution fk_auth_exec_realm; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.authentication_execution
    ADD CONSTRAINT fk_auth_exec_realm FOREIGN KEY (realm_id) REFERENCES public.realm(id);


--
-- Name: authentication_flow fk_auth_flow_realm; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.authentication_flow
    ADD CONSTRAINT fk_auth_flow_realm FOREIGN KEY (realm_id) REFERENCES public.realm(id);


--
-- Name: authenticator_config fk_auth_realm; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.authenticator_config
    ADD CONSTRAINT fk_auth_realm FOREIGN KEY (realm_id) REFERENCES public.realm(id);


--
-- Name: user_role_mapping fk_c4fqv34p1mbylloxang7b1q3l; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_role_mapping
    ADD CONSTRAINT fk_c4fqv34p1mbylloxang7b1q3l FOREIGN KEY (user_id) REFERENCES public.user_entity(id);


--
-- Name: client_scope_attributes fk_cl_scope_attr_scope; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.client_scope_attributes
    ADD CONSTRAINT fk_cl_scope_attr_scope FOREIGN KEY (scope_id) REFERENCES public.client_scope(id);


--
-- Name: client_scope_role_mapping fk_cl_scope_rm_scope; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.client_scope_role_mapping
    ADD CONSTRAINT fk_cl_scope_rm_scope FOREIGN KEY (scope_id) REFERENCES public.client_scope(id);


--
-- Name: protocol_mapper fk_cli_scope_mapper; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.protocol_mapper
    ADD CONSTRAINT fk_cli_scope_mapper FOREIGN KEY (client_scope_id) REFERENCES public.client_scope(id);


--
-- Name: client_initial_access fk_client_init_acc_realm; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.client_initial_access
    ADD CONSTRAINT fk_client_init_acc_realm FOREIGN KEY (realm_id) REFERENCES public.realm(id);


--
-- Name: component_config fk_component_config; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.component_config
    ADD CONSTRAINT fk_component_config FOREIGN KEY (component_id) REFERENCES public.component(id);


--
-- Name: component fk_component_realm; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.component
    ADD CONSTRAINT fk_component_realm FOREIGN KEY (realm_id) REFERENCES public.realm(id);


--
-- Name: realm_default_groups fk_def_groups_realm; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.realm_default_groups
    ADD CONSTRAINT fk_def_groups_realm FOREIGN KEY (realm_id) REFERENCES public.realm(id);


--
-- Name: user_federation_mapper_config fk_fedmapper_cfg; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_federation_mapper_config
    ADD CONSTRAINT fk_fedmapper_cfg FOREIGN KEY (user_federation_mapper_id) REFERENCES public.user_federation_mapper(id);


--
-- Name: user_federation_mapper fk_fedmapperpm_fedprv; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_federation_mapper
    ADD CONSTRAINT fk_fedmapperpm_fedprv FOREIGN KEY (federation_provider_id) REFERENCES public.user_federation_provider(id);


--
-- Name: user_federation_mapper fk_fedmapperpm_realm; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_federation_mapper
    ADD CONSTRAINT fk_fedmapperpm_realm FOREIGN KEY (realm_id) REFERENCES public.realm(id);


--
-- Name: associated_policy fk_frsr5s213xcx4wnkog82ssrfy; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.associated_policy
    ADD CONSTRAINT fk_frsr5s213xcx4wnkog82ssrfy FOREIGN KEY (associated_policy_id) REFERENCES public.resource_server_policy(id);


--
-- Name: scope_policy fk_frsrasp13xcx4wnkog82ssrfy; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scope_policy
    ADD CONSTRAINT fk_frsrasp13xcx4wnkog82ssrfy FOREIGN KEY (policy_id) REFERENCES public.resource_server_policy(id);


--
-- Name: resource_server_perm_ticket fk_frsrho213xcx4wnkog82sspmt; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.resource_server_perm_ticket
    ADD CONSTRAINT fk_frsrho213xcx4wnkog82sspmt FOREIGN KEY (resource_server_id) REFERENCES public.resource_server(id);


--
-- Name: resource_server_resource fk_frsrho213xcx4wnkog82ssrfy; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.resource_server_resource
    ADD CONSTRAINT fk_frsrho213xcx4wnkog82ssrfy FOREIGN KEY (resource_server_id) REFERENCES public.resource_server(id);


--
-- Name: resource_server_perm_ticket fk_frsrho213xcx4wnkog83sspmt; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.resource_server_perm_ticket
    ADD CONSTRAINT fk_frsrho213xcx4wnkog83sspmt FOREIGN KEY (resource_id) REFERENCES public.resource_server_resource(id);


--
-- Name: resource_server_perm_ticket fk_frsrho213xcx4wnkog84sspmt; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.resource_server_perm_ticket
    ADD CONSTRAINT fk_frsrho213xcx4wnkog84sspmt FOREIGN KEY (scope_id) REFERENCES public.resource_server_scope(id);


--
-- Name: associated_policy fk_frsrpas14xcx4wnkog82ssrfy; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.associated_policy
    ADD CONSTRAINT fk_frsrpas14xcx4wnkog82ssrfy FOREIGN KEY (policy_id) REFERENCES public.resource_server_policy(id);


--
-- Name: scope_policy fk_frsrpass3xcx4wnkog82ssrfy; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scope_policy
    ADD CONSTRAINT fk_frsrpass3xcx4wnkog82ssrfy FOREIGN KEY (scope_id) REFERENCES public.resource_server_scope(id);


--
-- Name: resource_server_perm_ticket fk_frsrpo2128cx4wnkog82ssrfy; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.resource_server_perm_ticket
    ADD CONSTRAINT fk_frsrpo2128cx4wnkog82ssrfy FOREIGN KEY (policy_id) REFERENCES public.resource_server_policy(id);


--
-- Name: resource_server_policy fk_frsrpo213xcx4wnkog82ssrfy; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.resource_server_policy
    ADD CONSTRAINT fk_frsrpo213xcx4wnkog82ssrfy FOREIGN KEY (resource_server_id) REFERENCES public.resource_server(id);


--
-- Name: resource_scope fk_frsrpos13xcx4wnkog82ssrfy; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.resource_scope
    ADD CONSTRAINT fk_frsrpos13xcx4wnkog82ssrfy FOREIGN KEY (resource_id) REFERENCES public.resource_server_resource(id);


--
-- Name: resource_policy fk_frsrpos53xcx4wnkog82ssrfy; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.resource_policy
    ADD CONSTRAINT fk_frsrpos53xcx4wnkog82ssrfy FOREIGN KEY (resource_id) REFERENCES public.resource_server_resource(id);


--
-- Name: resource_policy fk_frsrpp213xcx4wnkog82ssrfy; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.resource_policy
    ADD CONSTRAINT fk_frsrpp213xcx4wnkog82ssrfy FOREIGN KEY (policy_id) REFERENCES public.resource_server_policy(id);


--
-- Name: resource_scope fk_frsrps213xcx4wnkog82ssrfy; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.resource_scope
    ADD CONSTRAINT fk_frsrps213xcx4wnkog82ssrfy FOREIGN KEY (scope_id) REFERENCES public.resource_server_scope(id);


--
-- Name: resource_server_scope fk_frsrso213xcx4wnkog82ssrfy; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.resource_server_scope
    ADD CONSTRAINT fk_frsrso213xcx4wnkog82ssrfy FOREIGN KEY (resource_server_id) REFERENCES public.resource_server(id);


--
-- Name: composite_role fk_gr7thllb9lu8q4vqa4524jjy8; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.composite_role
    ADD CONSTRAINT fk_gr7thllb9lu8q4vqa4524jjy8 FOREIGN KEY (child_role) REFERENCES public.keycloak_role(id);


--
-- Name: user_consent_client_scope fk_grntcsnt_clsc_usc; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_consent_client_scope
    ADD CONSTRAINT fk_grntcsnt_clsc_usc FOREIGN KEY (user_consent_id) REFERENCES public.user_consent(id);


--
-- Name: user_consent fk_grntcsnt_user; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_consent
    ADD CONSTRAINT fk_grntcsnt_user FOREIGN KEY (user_id) REFERENCES public.user_entity(id);


--
-- Name: group_attribute fk_group_attribute_group; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.group_attribute
    ADD CONSTRAINT fk_group_attribute_group FOREIGN KEY (group_id) REFERENCES public.keycloak_group(id);


--
-- Name: group_role_mapping fk_group_role_group; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.group_role_mapping
    ADD CONSTRAINT fk_group_role_group FOREIGN KEY (group_id) REFERENCES public.keycloak_group(id);


--
-- Name: realm_enabled_event_types fk_h846o4h0w8epx5nwedrf5y69j; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.realm_enabled_event_types
    ADD CONSTRAINT fk_h846o4h0w8epx5nwedrf5y69j FOREIGN KEY (realm_id) REFERENCES public.realm(id);


--
-- Name: realm_events_listeners fk_h846o4h0w8epx5nxev9f5y69j; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.realm_events_listeners
    ADD CONSTRAINT fk_h846o4h0w8epx5nxev9f5y69j FOREIGN KEY (realm_id) REFERENCES public.realm(id);


--
-- Name: identity_provider_mapper fk_idpm_realm; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.identity_provider_mapper
    ADD CONSTRAINT fk_idpm_realm FOREIGN KEY (realm_id) REFERENCES public.realm(id);


--
-- Name: idp_mapper_config fk_idpmconfig; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.idp_mapper_config
    ADD CONSTRAINT fk_idpmconfig FOREIGN KEY (idp_mapper_id) REFERENCES public.identity_provider_mapper(id);


--
-- Name: web_origins fk_lojpho213xcx4wnkog82ssrfy; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.web_origins
    ADD CONSTRAINT fk_lojpho213xcx4wnkog82ssrfy FOREIGN KEY (client_id) REFERENCES public.client(id);


--
-- Name: scope_mapping fk_ouse064plmlr732lxjcn1q5f1; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scope_mapping
    ADD CONSTRAINT fk_ouse064plmlr732lxjcn1q5f1 FOREIGN KEY (client_id) REFERENCES public.client(id);


--
-- Name: protocol_mapper fk_pcm_realm; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.protocol_mapper
    ADD CONSTRAINT fk_pcm_realm FOREIGN KEY (client_id) REFERENCES public.client(id);


--
-- Name: credential fk_pfyr0glasqyl0dei3kl69r6v0; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.credential
    ADD CONSTRAINT fk_pfyr0glasqyl0dei3kl69r6v0 FOREIGN KEY (user_id) REFERENCES public.user_entity(id);


--
-- Name: protocol_mapper_config fk_pmconfig; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.protocol_mapper_config
    ADD CONSTRAINT fk_pmconfig FOREIGN KEY (protocol_mapper_id) REFERENCES public.protocol_mapper(id);


--
-- Name: default_client_scope fk_r_def_cli_scope_realm; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.default_client_scope
    ADD CONSTRAINT fk_r_def_cli_scope_realm FOREIGN KEY (realm_id) REFERENCES public.realm(id);


--
-- Name: required_action_provider fk_req_act_realm; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.required_action_provider
    ADD CONSTRAINT fk_req_act_realm FOREIGN KEY (realm_id) REFERENCES public.realm(id);


--
-- Name: resource_uris fk_resource_server_uris; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.resource_uris
    ADD CONSTRAINT fk_resource_server_uris FOREIGN KEY (resource_id) REFERENCES public.resource_server_resource(id);


--
-- Name: role_attribute fk_role_attribute_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.role_attribute
    ADD CONSTRAINT fk_role_attribute_id FOREIGN KEY (role_id) REFERENCES public.keycloak_role(id);


--
-- Name: realm_supported_locales fk_supported_locales_realm; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.realm_supported_locales
    ADD CONSTRAINT fk_supported_locales_realm FOREIGN KEY (realm_id) REFERENCES public.realm(id);


--
-- Name: user_federation_config fk_t13hpu1j94r2ebpekr39x5eu5; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_federation_config
    ADD CONSTRAINT fk_t13hpu1j94r2ebpekr39x5eu5 FOREIGN KEY (user_federation_provider_id) REFERENCES public.user_federation_provider(id);


--
-- Name: user_group_membership fk_user_group_user; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_group_membership
    ADD CONSTRAINT fk_user_group_user FOREIGN KEY (user_id) REFERENCES public.user_entity(id);


--
-- Name: policy_config fkdc34197cf864c4e43; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.policy_config
    ADD CONSTRAINT fkdc34197cf864c4e43 FOREIGN KEY (policy_id) REFERENCES public.resource_server_policy(id);


--
-- Name: identity_provider_config fkdc4897cf864c4e43; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.identity_provider_config
    ADD CONSTRAINT fkdc4897cf864c4e43 FOREIGN KEY (identity_provider_id) REFERENCES public.identity_provider(internal_id);


--
-- PostgreSQL database dump complete
--

