from __future__ import absolute_import, division, print_function
__metaclass__ = type

DOCUMENTATION = r'''
    name: rancher
    plugin_type: inventory
    author:
      - Osvaldo Toja
    short_description: Ansible dynamic inventory plugin for Rancher.
    version_added: "1.0"
    description:
        - Creates an inventory of imported clusters from Rancher server.
    options:
        plugin:
            description: the name of this plugin, it should always be set to 'rancher'
                for this plugin to recognize it as it's own.
            required: True
            choices: ['rancher']
        rancher_host:
            description: The network address of your rancher server.
            type: string
            required: True
        validate_certs:
            description: Enforce rancher server cert validation.
            type: string
            required: False
        labels_groups:
            description: Clusters labels become ansible host groups.
            type: list
            required: True
        managed_label:
            description: Label to identify the cluster is managed by this inventory.
            type: string
            required: False
'''

EXAMPLES = r'''
plugin: rancher
rancher_host: rancher.example.org
labels_groups: ['environment_stage', 'cloud_provider']
managed_label: 'ansible_managed'
'''

# import yaml
# import consul
import os
import requests
# from requests.exceptions import ConnectionError
from ansible.errors import AnsibleError, AnsibleParserError
from ansible.module_utils._text import to_native
from ansible.plugins.inventory import BaseInventoryPlugin
from requests.exceptions import HTTPError

# https://docs.ansible.com/ansible/latest/dev_guide/developing_inventory.html
class InventoryModule(BaseInventoryPlugin):

  NAME = 'rancher'

  def verify_file(self, path):
    '''Return true/false if this is possibly a valid file for this plugin to
    consume
    '''
    return True

  def _populate(self):
    '''Return the hosts and groups'''
    headers = {"Authorization": "Bearer "+ self._rancher_token}
    url = 'https://' + self.rancher_host + '/v3/clusters'
    try:
      # TODO: make cert verification configurable
      response = requests.get(url, headers=headers, verify=False)
    except requests.exceptions.RequestException as e:
      print(e)
      raise EnvironmentError('ERROR: Connection error while attempting to reach rancher_host. URL: %s ******' % url)
    # check for error codes (4xx or 5xx)
    try:
        response.raise_for_status()
    except requests.exceptions.HTTPError as e:
      print(e)
      raise EnvironmentError('ERROR: http error from rancher_host. URL: %s ******' % url)
    clusters = response.json()['data']
    # print(clusters)
    # TODO: manage pagination for large number of clusters
    # "pagination": {
    #   "limit": 1000,
    #   "total": 17
    # },
    for cluster in clusters:
      if 'labels' in cluster:
        labels = cluster['labels']
        if self.managed_label in labels and labels[self.managed_label] == 'true':
          for group in self.labels_groups:
            if group in labels:
              self.inventory.add_group(labels[group])
              self.inventory.add_host(host=cluster['name'], group=labels[group])
              # self.inventory.add_group('nonprod')
              # self.inventory.add_host(host='marsh-nonprod', group='nonprod')

  def parse(self, inventory, loader, path, cache):
    '''Return dynamic inventory from source '''
    super(InventoryModule, self).parse(inventory, loader, path, cache)
    # TODO: using environment variables for v1, use config file for v2
    self._rancher_token = os.getenv('RANCHER_BEARER_TOKEN')
    rancher_host = os.getenv('RANCHER_HOST')
    if self._rancher_token is None or len(self._rancher_token) == 0:
      raise EnvironmentError(f'Failed because RANCHER_BEARER_TOKEN is not set')
    # Read the inventory YAML file
    self._read_config_data(path)
    try:
        # Store the options from the YAML file
        self.plugin = self.get_option('plugin')
        self.rancher_host =  self.get_option('rancher_host')
        # useful for development
        self.rancher_host = self.get_option('rancher_host') if rancher_host is None or len(rancher_host) == 0 else rancher_host
        self.labels_groups = self.get_option('labels_groups')
        self.managed_label = self.get_option('managed_label')

    except Exception as e:
        raise AnsibleParserError(
            'All correct options required: {}'.format(e))
    # Call our internal helper to populate the dynamic inventory
    self._populate()



