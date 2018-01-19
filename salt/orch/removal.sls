# must provide the node (id) to be removeed in the 'target' pillar
{%- set target = salt['pillar.get']('target') %}

sync-pillar:
  salt.runner:
    - name: saltutil.sync_pillar

update-pillar:
  salt.function:
    - tgt: '*'
    - name: saltutil.refresh_pillar
    - require:
      - sync-pillar

update-grains:
  salt.function:
    - tgt: '*'
    - name: saltutil.refresh_grains
    - require:
       - update-pillar

update-mine:
  salt.function:
    - tgt: '*'
    - name: mine.update
    - require:
       - update-grains

update-modules:
  salt.function:
    - name: saltutil.sync_modules
    - tgt: '*'
    - kwarg:
        refresh: True
    - require:
      - update-mine

{%- set masters = salt.saltutil.runner('mine.get', tgt='G@roles:kube-master', fun='network.interfaces', tgt_type='compound').keys() %}
{%- if target in masters %}
  # TODO: we should promote a worker, but this is too hard to do right now
  #       just log a message for now
  {%- do salt.caasp_log.warn('removing a k8s master: it will not be replaced') %}
{%- endif %}

{%- set etcd_members = salt.saltutil.runner('mine.get', tgt='G@roles:etcd', fun='network.interfaces', tgt_type='compound').keys() %}
{%- if target in etcd_members %}
  # if the node is a member of the etcd cluster:
  # we must choose another node and promote it to be an etcd master
  {%- set non_etcd_members = salt.saltutil.runner('mine.get', tgt='not G@roles:etcd', fun='network.interfaces', tgt_type='compound').keys() %}
  {%- if non_etcd_members|length > 0 %}
    {%- set new_etcd_member = non_etcd_members|first %}
    # promote some other node to be a full member of the etcd cluster
    # WARNING: we should do a consistency check in Velum...
etcd-add-member:
  salt.state:
    - tgt: '{{ new_etcd_member }}'
    - sls:
      - etcd.remove-pre-stop-services
    - require:
      - update-modules
  {%- endif %}

  # remove the etcd member running in {{ target }}
etcd-remove-member:
  salt.state:
    - tgt: '{{ target }}'
    - sls:
      - etcd.remove-pre-stop-services
    - require:
    {%- if non_etcd_members|length > 0 %}
      - etcd-add-member
    {%- else %}
      - update-modules
    {%- endif %}

{%- endif %}

update-grains-again:
  salt.function:
    - tgt: '*'
    - name: saltutil.refresh_grains
    - require:
    {%- if target in etcd_members %}
      - etcd-remove-member
    {%- else %}
      - update-modules
    {%- endif %}

stop-services:
  salt.state:
    - tgt: {{ target }}
    - sls:
      - container-feeder.stop
      {%- if target in masters %}
      - kube-apiserver.stop
      - kube-controller-manager.stop
      - kube-scheduler.stop
      {%- else %}
      - kubelet.stop
      - kube-proxy.stop
      {%- endif %}
      - docker.stop
      - etcd.stop
    - require:
      - update-grains-again

# remove any other configuration in the machines
# TODO: all the files in /etc/kubernetes/*, /var/lib/kubernetes/* ??
remove-pre-reboot:
  salt.state:
    - tgt: {{ target }}
    - sls:
      - container-feeder.remove-pre-reboot
      {%- if target in masters %}
      - kube-apiserver.remove-pre-reboot
      - kube-controller-manager.remove-pre-reboot
      - kube-scheduler.remove-pre-reboot
      {%- else %}
      - kubelet.remove-pre-reboot
      - kube-proxy.remove-pre-reboot
      {%- endif %}
      - docker.remove-pre-reboot
      - cni.remove-pre-reboot
      - etcd.remove-pre-reboot
    - require:
      - stop-services

# shutdown the node
shutdown-node:
  salt.function:
    - tgt: {{ target }}
    - name: cmd.run
    - arg:
      - sleep 15; systemctl poweroff
    - kwarg:
        bg: True
    - require:
      - remove-pre-reboot

# we don't need to wait for the node: just forget about it...

# revoke Salt keys
remove-salt-key:
  salt.wheel:
    - name: key.delete
    - match: {{ target }}
    - require:
      - shutdown-node

# revoke certificates
# TODO
