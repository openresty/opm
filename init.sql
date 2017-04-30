-- the following commented commands should be run by a super user of postgres:
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

drop table if exists uploads cascade;

-- for user module uploads
create table uploads (
    id serial primary key,
    uploader integer references users(id) not null,
    org_account integer references orgs(id),  -- only take a value when the
                                              -- account != uploader
    orig_checksum uuid not null,  -- MD5 checksum for the original pkg
    final_checksum uuid,          -- MD5 checksum for the final pkg
    size integer not null,
    package_name varchar(256) not null,
    abstract text,

    version_v integer[] not null,
    version_s varchar(128) not null,

    authors text[],
    licenses text[],
    is_original boolean,
    repo_link varchar(1024),

    dep_packages text[],
    dep_operators varchar(2)[],
    dep_versions text[],

    client_addr inet not null,
    failed boolean not null default FALSE,
    indexed boolean not null default FALSE,

    ts_idx tsvector,

    created_at timestamp with time zone not null default now(),
    updated_at timestamp with time zone not null default now()
);

drop function if exists uploads_trigger() cascade;

create function uploads_trigger() returns trigger as $$
begin
      new.ts_idx :=
         setweight(to_tsvector('pg_catalog.english', coalesce(new.package_name,'')), 'A')
         || setweight(to_tsvector('pg_catalog.english', coalesce(new.abstract,'')), 'D');
      return new;
end
$$ language plpgsql;

create trigger tsvectorupdate before insert or update
    on uploads for each row execute procedure uploads_trigger();

create index ts_idx on uploads using gin(ts_idx);

update uploads set package_name = package_name;

drop function if exists first_agg(anyelement, anyelement) cascade;

create or replace function first_agg(anyelement, anyelement)
returns anyelement language sql immutable strict as $$
        select $1;
$$;

create aggregate first (
        sfunc    = first_agg,
        basetype = anyelement,
        stype    = anyelement
);

drop function if exists last_agg(anyelement, anyelement) cascade;

create or replace function last_agg(anyelement, anyelement)
returns anyelement language sql immutable strict as $$
        select $1;
$$;

create aggregate last (
        sfunc    = last_agg,
        basetype = anyelement,
        stype    = anyelement
);

-- TODO create more indexes to speed up queries in the opmserver web app.
