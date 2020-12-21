# Ansible inventory

This role uses the rancher inventory plugin. The plugin provides list of clusters from a rancher server as an ansible inventory.

Rancher clustes become ansible hosts. Ansible groups are dynamically created based on a set of labels provided by the inventory plugin configuration file.

# Group/Host variables

```
$ tree .
.
├── group_vars
│   ├── all.yml
│   ├── aws.yml
│   ├── azure.yml
│   ├── production.yml
│   └── staging.yml
├── host_vars
│   └── demo1.yml
└── rancher.yml
```

* rancher.yml: The inventory plugin configuration file. Its presence enable the plugin.
* group_vars: Values are automatically assigned based on group membership for clusters.
* host_vars: To override and provide custom variables for specific clusters.

# Charts

A balance between flexibility and customization is provided by defining charts based on group membership.

Charts are defined in variables from inventory group files. Each group defines a variable relevant to the group itself, leaving to role's `task/main.yml` file to define merging logic.

* Common charts to all clusters are defined in the variable: `default_charts`, in `group_vars/all.yml` file.
* Group files define relevant variables accordindly: cloud related groups use `cloud_charts`, environment stage use `environment_charts`.

## What if we want to use the role to deploy only a chart (or group of) to a single cluster?

The `overrideCharts` variable can be defined in the host file, and will take precedence over existing `charts` variable.

# Labels

The inventory plugin relies on labels assigned to the imported cluster.

Example labels:

```
environment_stage=production
k8s_distro=eks
cloud_provider=aws
ansible_managed=true
```

Only clusters with `ansible_managed=true` label will be added to the inventory, otherwise they will ignored. This is nice safety measure when working with an existing production rancher server.

The configuration file for the inventory plugin provides the list of labels to be used for creating host groups in the inventory. 

The values of the labels will be used to create host groups, but the one defined as `managed_label`, from the inventory plugin file `rancher.yml`:

```
labels_groups: ['environment_stage', 'cloud_provider', 'ansible_managed']
managed_label: 'ansible_managed'
```


# Helm

Available `helm` module for ansible 2.9 or earlier versions is targetted for helm v2. Ansible 2.10 provides a[ `helm` module](https://docs.ansible.com/ansible/latest/collections/community/general/helm_module.html) using helm v3.

This project uses ansible 2.9, the trade-off was to run helm v3 from the command line, but using a syntax for the charts similar to the one used by the newest helm module.

helm v3 module:

```yaml
- name: Install helm chart
  community.general.helm:
    host: localhost
    chart:
      name: memcached
      version: 0.4.0
      source:
        type: repo
        location: https://kubernetes-charts.storage.googleapis.com
    state: present
    name: my-memcached
    namespace: default
```

Role charts variable:
```yaml
default_charts:
  podinfo:
    chart_name: "podinfo"
    namespace: "default"
    chart_version: "5.1.1"
    state: present
    source:
      type: repo
      location: https://stefanprodan.github.io/podinfo
      name: podinfo
    values:
      ui:
        message: "Hello world from ansible group_vars default"
        color: "#34577c"
```

## Helm chart values

Custom values can be added via the `values` key in chart's variable. In order to allow for child keys to be properly merged, we use `recursive=True` property for the `combine` jinja filter.

```yaml
- name: get list of default and cloud charts
  set_fact:
    charts: "{{ default_charts | combine(cloud_charts, recursive=True) }}"
```    

## pre/post install manifests

The original idea was to replace rancher apps with a more flexible solution. Rancher apps are helm charts. Helm charts have support for hooks, but adding a pre/post install manifest to an existing hook it's not a trivial task.

To allow for this level of customization, the role comes with support for custom manifests. 

If you want to deploy resources after executing `helm install <chart-name>`, you can create a file (template actually): `templates/<chart-name>/manifests/post.yaml.j2`. A similar approach for pre-install manifests should be easy to implement.

> The `lookup` plugin used with `first_found` allows for customized templates.

