-- create user opm with password 'buildecosystem';
-- create database opm;
-- grant all privileges on database opm to opm;

drop table if exists users cascade;

-- for github users
create table users (
    id serial primary key,
    login varchar(64) not null unique,

    name varchar(128),
    avatar_url varchar(1024),
    bio text,
    blog varchar(1024),
    company varchar(128),
    location text,

    followers integer not null,
    following integer not null,

    public_email varchar(128),
    verified_email varchar(128),

    public_repos integer not null,

    github_created_at timestamp with time zone not null,
    github_updated_at timestamp with time zone not null,

    created_at timestamp with time zone not null default now(),
    updated_at timestamp with time zone not null default now()
);

drop table if exists orgs cascade;

-- for github organizations
create table orgs (
    id serial primary key,
    login varchar(64) not null unique,

    name varchar(128),
    avatar_url varchar(1024),
    description text,
    blog varchar(1024),
    company varchar(128),
    location text,

    public_email varchar(128),
    public_repos integer not null,

    github_created_at timestamp with time zone not null,
    github_updated_at timestamp with time zone not null,

    created_at timestamp with time zone not null default now(),
    updated_at timestamp with time zone not null default now()
);

drop table if exists org_ownership cascade;

-- for github organization ownership among github users
create table org_ownership (
    id serial primary key,
    user_id integer references users(id) not null,
    org_id integer references orgs(id) not null
);

drop table if exists access_tokens cascade;

-- for github personal access tokens (we do not store too permissive tokens)
create table access_tokens (
    id serial primary key,
    user_id integer references users(id) not null,
    token_hash text not null,
    scopes text,
    created_at timestamp with time zone not null default now(),
    updated_at timestamp with time zone not null default now()
);

drop table if exists packages cascade;

-- for package names
create table packages (
    id serial primary key,
    name varchar(128) not null unique
);

drop table if exists uploads cascade;

-- for user module uploads
create table uploads (
    id serial primary key,
    uploader integer references users(id) not null,
    org_account integer references orgs(id),  -- only take a value when the
                                              -- account != uploader
    checksum uuid not null,  -- MD5 checksum
    size integer not null,
    name varchar(128) not null,
    abstract text,

    version_v integer[] not null,
    version_s varchar(128) not null,

    authors text[],
    licenses text[],
    is_original boolean,
    repo_link varchar(1024),

    dep_packages integer[],  -- references packages(id)
    dep_versions text[],

    client_addr inet not null,
    processed boolean not null default FALSE,
    indexed boolean not null default FALSE,

    created_at timestamp with time zone not null default now(),
    updated_at timestamp with time zone not null default now()
);
