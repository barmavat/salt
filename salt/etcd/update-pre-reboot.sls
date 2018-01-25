{% set roles = salt['grains.get']('roles', []) %}
{% set has_etcd_role = ("etcd" in roles) %}

{% set is_etcd_member = salt['file.directory_exists' ]('/var/lib/etcd/member') and
                    not salt['file.directory_exists' ]('/var/lib/etcd/proxy') %}

{%- if is_etcd_member and not has_etcd_role -%}
  # this is really running a member of the etcd cluster but it doesn't
  # have the 'etcd' role: set the 'etcd' role so we are sure it will be
  # running etcd after the update

add-etcd-role:
  grains.append:
    - name: roles
    - value: etcd

{% else %}
  # in other case (ie, this was a proxy in the past) make sure
  # there is nothing left in /var/lib/etcd

cleanup-old-etcd-stuff:
  cmd.run:
    - name: rm -rf /var/lib/etcd/*

uninstall-etcd:
  # we cannot remove the etcd package, so we can only
  # make sure that the service is disabled
  service.disabled:
    - name: etcd

{%- endif %}
