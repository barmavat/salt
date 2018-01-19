from __future__ import absolute_import

import logging

log = logging.getLogger(__name__)

# minimum number of etcd masters we recommend
MIN_RECOMMENDED_MEMBER_COUNT = 3

# port where etcd listens for clients
ETCD_CLIENT_PORT = 2379


def __virtual__():
    return "caasp_etcd"


# the grain that is used for obtaining node names
# make sure it is in the pillar/mine.sls
_GRAIN_NAME = 'nodename'


class NoEtcdServersException(Exception):
    pass


def _optimal_etcd_number(num_nodes):
    if num_nodes >= 7:
        return 7
    elif num_nodes >= 5:
        return 5
    elif num_nodes >= 3:
        return 3
    else:
        return 1


def _get_num_kube(expr):
    """
    Get the number of kubernetes nodes that in the cluster that match "expr"
    """
    log.debug("Finding nodes that match '%s' in the cluster", expr)
    nodes = __salt__['mine.get'](expr, _GRAIN_NAME, expr_form='grain').values()
    # 'mine.get' is not available in the master, so it will return nothing
    # in that case, we can try again with saltutil.runner... uh?
    if not nodes:
        log.debug("... using 'saltutil.runner' for getting the '%s' nodes", expr)
        nodes = __salt__['saltutil.runner']('mine.get',
                                            tgt=expr, fun=_GRAIN_NAME, tgt_type='grain').values()
    return len(nodes)


def get_cluster_size():
    """
    Determines the etcd discovery cluster size

    Determines the desired number of cluster members, defaulting to
    the value supplied in the etcd:masters pillar, falling back to
    match the number nodes with the kube-master role, and if this is
    less than 3, it will bump it to 3 (or the number of nodes
    available if the number of nodes is less than 3).
    """
    member_count = __salt__['pillar.get']('etcd:masters', None)

    if not member_count:
        # A value has not been set in the pillar, calculate a "good" number
        # for the user.
        num_masters = _get_num_kube("roles:kube-master")

        member_count = _optimal_etcd_number(num_masters)
        if member_count < MIN_RECOMMENDED_MEMBER_COUNT:
            # Attempt to increase the number of etcd master to 3,
            # however, if we don't have 3 nodes in total,
            # then match the number of nodes we have.
            increased_member_count = _get_num_kube("roles:kube-*")
            increased_member_count = min(
                MIN_RECOMMENDED_MEMBER_COUNT, increased_member_count)

            # ... but make sure we are using an odd number
            # (otherwise we could have some leader election problems)
            member_count = _optimal_etcd_number(increased_member_count)

            log.warning("etcd member count too low (%d), increasing to %d",
                        num_masters, increased_member_count)
    else:
        # A value has been set in the pillar, respect the users choice
        # even it's not a "good" number.
        member_count = int(member_count)

        if member_count < MIN_RECOMMENDED_MEMBER_COUNT:
            log.warning("etcd member count too low (%d), consider increasing "
                        "to %d", member_count, MIN_RECOMMENDED_MEMBER_COUNT)

    member_count = max(1, member_count)
    log.debug("using member count = %d", member_count)
    return member_count


def etcdctl_args(skip_this=False, etcd_members=[]):
    """
    Build the list of args for 'etcdctl'
    """
    etcdctl_args = ""
    etcdctl_args += " --ca-file " + __salt__['pillar.get']('ssl:ca_file')
    etcdctl_args += " --key-file " + __salt__['pillar.get']('ssl:key_file')
    etcdctl_args += " --cert-file " + __salt__['pillar.get']('ssl:crt_file')

    this_name = __salt__['grains.get'](_GRAIN_NAME)

    # build the list of etcd masters
    if len(etcd_members) == 0:
        etcd_members = __salt__["mine.get"](
            "G@roles:etcd", _GRAIN_NAME, expr_form="compound").values()

    etcd_members_urls = []
    for name in etcd_members:
        if skip_this and name == this_name:
            continue
        url = "https://{}:{}".format(name, ETCD_CLIENT_PORT)
        etcd_members_urls.append(url)

    if len(etcd_members) == 0:
        log.error("no etcd members available for etcdctl!!")
        raise NoEtcdServersException()

    etcdctl_args += " --endpoints " + ",".join(etcd_members_urls)

    return etcdctl_args
