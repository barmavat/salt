{%- set this_id = grains['id'] %}
{%- set this_roles = salt['grains.get']('roles') %}

{%- if 'etcd' in this_roles  %}

  # this is a member of the etcd cluster:
  # remove it from the cluster

etcd-remove-member:
  caasp_cmd.run:
    # explicitly remove the node from the etcd cluster, so it is not
    # considered a node suffering some transient failure...
    - name:
        etcdctl {{ salt.caasp_etcd.etcdctl_args(skip_this=True) }} member remove {{ this_id }}
    - retry:
        attempts: 3
  # we cannot remove the etcd role: otherwise it will not
  # be stopped/cleaned up

  {%- else %}

include:
  - etcd

    # etcd was not running in this node: we are replacing
    # an etcd member.
    # then we 1) add the `etcd` role and then 2) apply high state

etcd-add-member:
  grains.list_present:
    - name: roles
    - value: etcd
    - require_in:
      - etcd
      {#- ^ this will apply the etcd states in the new etcd member -#}

  {%- endif %}
{%- endif %}
