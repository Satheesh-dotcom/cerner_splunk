
# frozen_string_literal: true

#
# Cookbook Name:: cerner_splunk
# Recipe:: shc_deployer
#
# Configures the Deployer in a Search Head Cluster

raise 'Deployer installation not currently supported on windows' if platform_family?('windows')

search_heads = CernerSplunk.my_cluster_data(node)['shc_members']

raise 'Search Heads are not configured for sh clustering in the cluster databag' if search_heads.nil? || search_heads.empty?

instance_exec :shc_deployer, &CernerSplunk::NODE_TYPE

include_recipe 'cerner_splunk::_install_server'

execute 'apply-shcluster-bundle' do # ~FC009
  command(lazy { "#{node['splunk']['cmd']} apply shcluster-bundle -target '#{search_heads.first}' --answer-yes -auth admin:#{node.run_state['cerner_splunk']['admin-password']}" })
  environment 'HOME' => node['splunk']['home']
  action :nothing
  sensitive true
end

cluster_data = CernerSplunk.my_cluster_data(node) || {}

cluster_bag = CernerSplunk::DataBag.load(cluster_data['apps'], pick_context: ['deployer-apps']) || {}

global_apps_bag = CernerSplunk::DataBag.load(cluster_bag['bag']) || {}

apps = CernerSplunk::AppHelpers.merge_hashes(global_apps_bag, cluster_bag)

# Basic configs for the _shcluster app
app_configs = {
  'files' => {
    'app.conf' => {
      'ui' => {
        'is_visible' => '0',
        'label' => 'Deployer Configs App'
      }
    },
    'ui-prefs.conf' => node['splunk']['config']['ui_prefs']
  },
  'permissions' => {
    '' => {
      'access' => { 'read' => '*' },
      'export' => 'system'
    }
  }
}

{ '_shcluster' => app_configs }.merge(apps).each do |app_name, app_data|
  download_data = app_data['download'] || {}
  app_data['files'] ||= {}
  app_data['lookups'] ||= {}

  app_type = download_data['url'] ? :splunk_app_package : :splunk_app_custom

  declare_resource(app_type, app_name) do
    action app_data['remove'] ? :uninstall : :install
    source_url download_data['url'] if download_data['url']
    version download_data['version'] if download_data['version']
    app_root :shcluster

    configs CernerSplunk::AppHelpers.proc_conf(app_data['files'])
    files CernerSplunk::AppHelpers.proc_files(files: app_data['files'], lookups: app_data['lookups'])
    metadata app_data['permissions']
    notifies :run, 'execute[apply-shcluster-bundle]'
  end
end

include_recipe 'cerner_splunk::_configure_shc_roles'
include_recipe 'cerner_splunk::_configure_shc_authentication'
include_recipe 'cerner_splunk::_configure_shc_outputs'
include_recipe 'cerner_splunk::_configure_shc_alerts'
include_recipe 'cerner_splunk::_start'
