# frozen_string_literal: true

require 'spec_helper'

def windows_config_params(ensure_val = 'present')
  {
    ensure: ensure_val,
    path: 'C:/Program Files/Metricbeat/metricbeat.yml',
    validate_cmd: '"C:\\Program Files\\Metricbeat\\metricbeat.exe" test config -c "%"',
  }
end

def linux_config_params(ensure_val = 'present')
  {
    ensure: ensure_val,
    owner: 'root',
    group: 'root',
    mode: '0600',
    path: '/etc/metricbeat/metricbeat.yml',
    validate_cmd: '/usr/share/metricbeat/bin/metricbeat test config -c %',
  }
end

def expected_config_params(os_facts, ensure_val = 'present')
  ((os_facts[:kernel] == 'windows') ? windows_config_params(ensure_val) : linux_config_params(ensure_val))
end

def yumrepo_params(version)
  {
    baseurl: "https://artifacts.elastic.co/packages/#{version}.x/yum",
    enabled: 1,
    gpgcheck: 1,
    gpgkey: 'https://artifacts.elastic.co/GPG-KEY-elasticsearch',
  }
end

def apt_source_params(version)
  {
    location: "https://artifacts.elastic.co/packages/#{version}.x/apt",
    release: 'stable',
    repos: 'main',
    key: {
      'id' => '46095ACC8548582C1A2699A9D27D666CD88E42B4',
      'source' => 'https://artifacts.elastic.co/GPG-KEY-elasticsearch',
    },
  }
end

def zypprepo_params(version)
  yumrepo_params(version).merge(autorefresh: 1, name: 'beats', type: 'yum')
end

def service_defaults
  {
    ensure: 'running',
    enable: true,
    hasrestart: true,
  }
end

describe 'metricbeat' do
  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts }

      it { is_expected.to compile }

      describe 'metricbeat::config' do
        it { is_expected.to contain_file('metricbeat.yml').with(expected_config_params(os_facts)) }
      end

      describe 'metricbeat::config with ensure = absent' do
        let(:params) { { 'ensure' => 'absent' } }

        it { is_expected.not_to contain_file('metricbeat.yml').with(expected_config_params(os_facts, 'absent')) }
      end

      describe 'metricbeat::config with disable_configtest = true' do
        let(:params) { { 'disable_configtest' => true } }

        it { is_expected.to contain_file('metricbeat.yml').with(expected_config_params(os_facts).merge(validate_cmd: nil)) }
      end

      describe 'metricbeat::config with config_mode = 0644' do
        let(:params) { { 'config_mode' => '0644' } }

        it { is_expected.to contain_file('metricbeat.yml').with(expected_config_params(os_facts).merge(mode: '0644')) } unless os_facts[:kernel] == 'windows'
      end

      describe 'metricbeat::config with config_mode = 9999' do
        let(:params) { { 'config_mode' => '9999' } }

        it { is_expected.to raise_error(Puppet::Error) }
      end

      describe 'metricbeat::config with major_version = 9 for new config test flag' do
        let(:params) { { 'major_version' => '9' } }
        let(:v9_validate_cmd) do
          if os_facts[:kernel] == 'windows'
            '"C:\\Program Files\\Metricbeat\\metricbeat.exe" test config -c "%"'
          else
            '/usr/share/metricbeat/bin/metricbeat test config -c %'
          end
        end

        it { is_expected.to contain_file('metricbeat.yml').with(expected_config_params(os_facts).merge(validate_cmd: v9_validate_cmd)) }
      end

      describe 'metricbeat::install' do
        if os_facts[:kernel] == 'windows'
          context 'with shell extractor' do
            let(:params) { { 'extract_method' => 'shell' } }
            let(:shell_cmd) do
              "$sh=New-Object -COM Shell.Application;$sh.namespace((Convert-Path 'C:/Program Files')).Copyhere(" \
                "$sh.namespace((Convert-Path 'C:/Windows/Temp/metricbeat-9.5.7-windows-x86_64.zip')).items(), 16)"
            end

            it do
              expect(catalogue).to contain_exec('unzip metricbeat-9.5.7-windows-x86_64').with(
                command: shell_cmd,
                creates: 'C:/Program Files/Metricbeat/metricbeat-9.5.7-windows-x86_64',
              )
            end
          end

          it { is_expected.to contain_file('C:/Program Files').with(ensure: 'directory') }

          it do
            expect(catalogue).to contain_archive('C:/Windows/Temp/metricbeat-9.5.7-windows-x86_64.zip').with(
              creates: 'C:/Program Files/Metricbeat/metricbeat-9.5.7-windows-x86_64',
              source: 'https://artifacts.elastic.co/downloads/beats/metricbeat/metricbeat-9.5.7-windows-x86_64.zip',
            )
          end

          it do
            expect(catalogue).to contain_exec('stop service metricbeat-9.5.7-windows-x86_64').with(
              creates: 'C:/Program Files/Metricbeat/metricbeat-9.5.7-windows-x86_64',
              command: 'Set-Service -Name metricbeat -Status Stopped',
              onlyif: 'if(Get-WmiObject -Class Win32_Service -Filter "Name=\'metricbeat\'") {exit 0} else {exit 1}',
            )
          end

          it do
            expect(catalogue).to contain_exec('rename metricbeat-9.5.7-windows-x86_64').with(
              creates: 'C:/Program Files/Metricbeat/metricbeat-9.5.7-windows-x86_64',
              command: "Remove-Item 'C:/Program Files/Metricbeat' -Recurse -Force -ErrorAction SilentlyContinue;" \
                       "Rename-Item 'C:/Program Files/metricbeat-9.5.7-windows-x86_64' 'C:/Program Files/Metricbeat'",
            )
          end

          it do
            expect(catalogue).to contain_exec('mark metricbeat-9.5.7-windows-x86_64').with(
              creates: 'C:/Program Files/Metricbeat/metricbeat-9.5.7-windows-x86_64',
              command: "New-Item 'C:/Program Files/Metricbeat/metricbeat-9.5.7-windows-x86_64' -ItemType file",
            )
          end

          it do
            expect(catalogue).to contain_exec('install metricbeat-9.5.7-windows-x86_64').with(
              command: './install-service-metricbeat.ps1',
              cwd: 'C:/Program Files/Metricbeat',
              refreshonly: true,
            )
          end
        else
          it { is_expected.to contain_package('metricbeat').with(ensure: 'present') }
        end
      end

      unless os_facts[:kernel] == 'windows'
        describe 'metricbeat::install with ensure = absent' do
          let(:params) { { 'ensure' => 'absent' } }

          it { is_expected.to contain_package('metricbeat').with(ensure: 'absent') }
        end

        describe 'metricbeat::install with package_ensure to a specific version' do
          let(:params) { { 'package_ensure' => '9.5.7' } }

          it { is_expected.to contain_package('metricbeat').with(ensure: '9.5.7') }
        end

        describe 'metricbeat::install with package_ensure = latest' do
          let(:params) { { 'package_ensure' => 'latest' } }

          it { is_expected.to contain_package('metricbeat').with(ensure: 'latest') }
        end
      end

      describe 'metricbeat::repo' do
        case os_facts[:osfamily]
        when 'RedHat'
          it { is_expected.to contain_yumrepo('beats').with(yumrepo_params(9)) }
        when 'Debian'
          it { is_expected.to contain_class('apt') }
          it { is_expected.to contain_class('apt::update').that_comes_before('Package[metricbeat]') }
          it { is_expected.to contain_apt__source('beats').with(apt_source_params(9)) }
        when 'SuSe'
          it { is_expected.to contain_zypprepo('beats').with(zypprepo_params(9)) }
        end
      end

      describe 'metricbeat::repo with major_version = 8' do
        let(:params) { { 'major_version' => '8' } }

        case os_facts[:osfamily]
        when 'RedHat'
          it { is_expected.to contain_yumrepo('beats').with(yumrepo_params(8)) }
        when 'Debian'
          it { is_expected.to contain_class('apt') }
          it { is_expected.to contain_apt__source('beats').with(apt_source_params(8)) }
        when 'SuSe'
          it { is_expected.to contain_zypprepo('beats').with(zypprepo_params(8)) }
        end
      end

      describe 'metricbeat::repo with major_version = 9' do
        let(:params) { { 'major_version' => '9' } }

        case os_facts[:osfamily]
        when 'RedHat'
          it { is_expected.to contain_yumrepo('beats').with(yumrepo_params(9)) }
        when 'Debian'
          it { is_expected.to contain_class('apt') }
          it { is_expected.to contain_apt__source('beats').with(apt_source_params(9)) }
        when 'SuSe'
          it { is_expected.to contain_zypprepo('beats').with(zypprepo_params(9)) }
        end
      end

      describe 'metricbeat::repo with major_version = idontknow' do
        let(:params) { { 'major_version' => 'idontknow' } }

        it { is_expected.to raise_error(Puppet::Error) }
      end

      describe 'metricbeat::service' do
        it { is_expected.to contain_service('metricbeat').with(service_defaults) }
      end

      describe 'metricbeat::service with ensure = absent' do
        let(:params) { { 'ensure' => 'absent' } }

        it { is_expected.to contain_service('metricbeat').with(service_defaults.merge(ensure: 'stopped', enable: false)) }
      end

      describe 'metricbeat::service with service_has_restart = false' do
        let(:params) { { 'service_has_restart' => false } }

        it { is_expected.to contain_service('metricbeat').with(service_defaults.merge(hasrestart: false)) }
      end

      describe 'metricbeat::service with service_ensure = disabled' do
        let(:params) { { 'service_ensure' => 'disabled' } }

        it { is_expected.to contain_service('metricbeat').with(service_defaults.merge(ensure: 'stopped', enable: false)) }
      end

      describe 'metricbeat::service with service_ensure = running' do
        let(:params) { { 'service_ensure' => 'running' } }

        it { is_expected.to contain_service('metricbeat').with(service_defaults.merge(enable: false)) }
      end

      describe 'metricbeat::service with service_ensure = unmanaged' do
        let(:params) { { 'service_ensure' => 'unmanaged' } }

        it { is_expected.to contain_service('metricbeat').with(service_defaults.merge(ensure: nil, enable: false)) }
      end

      context 'with elasticsearch output' do
        let(:params) do
          {
            'modules' => [{ 'module' => 'system', 'metricsets' => ['cpu', 'memory'], 'period' => '10s' }],
            'outputs' => { 'elasticsearch' => { 'hosts' => ['http://localhost:9200'] } },
          }
        end

        it { is_expected.to compile }
        it { is_expected.to contain_class('metricbeat::config').that_notifies('Class[metricbeat::service]') }
        it { is_expected.to contain_class('metricbeat::install').that_comes_before('Class[metricbeat::config]') }
        it { is_expected.to contain_class('metricbeat::repo').that_comes_before('Class[metricbeat::install]') }
        it { is_expected.to contain_class('metricbeat::service') }
      end

      context 'with manage_repo = false' do
        let(:params) do
          {
            'manage_repo' => false,
            'modules' => [{ 'module' => 'system', 'metricsets' => ['cpu', 'memory'], 'period' => '10s' }],
            'outputs' => { 'elasticsearch' => { 'hosts' => ['http://localhost:9200'] } },
          }
        end

        it { is_expected.to compile }
        it { is_expected.to contain_class('metricbeat::config').that_notifies('Class[metricbeat::service]') }
        it { is_expected.to contain_class('metricbeat::install').that_comes_before('Class[metricbeat::config]') }
        it { is_expected.not_to contain_class('metricbeat::repo') }
        it { is_expected.to contain_class('metricbeat::service') }
      end

      context 'with ensure = absent' do
        let(:params) do
          {
            'ensure' => 'absent',
            'modules' => [{ 'module' => 'system', 'metricsets' => ['cpu', 'memory'], 'period' => '10s' }],
            'outputs' => { 'elasticsearch' => { 'hosts' => ['http://localhost:9200'] } },
          }
        end

        it { is_expected.to compile }
        it { is_expected.not_to contain_class('metricbeat::config').that_comes_before('Class[metricbeat::service]') }
        it { is_expected.to contain_class('metricbeat::install') }
        it { is_expected.to contain_class('metricbeat::repo').that_comes_before('Class[metricbeat::install]') }
        it { is_expected.to contain_class('metricbeat::service').that_comes_before('Class[metricbeat::install]') }
      end

      context 'with ensure = idontknow' do
        let(:params) { { 'ensure' => 'idontknow' } }

        it { is_expected.to raise_error(Puppet::Error) }
      end

      context 'with service_ensure = thisisnew' do
        let(:params) { { 'service_ensure' => 'thisisnew' } }

        it { is_expected.to raise_error(Puppet::Error) }
      end

      context 'with multiple modules' do
        let(:params) do
          {
            'ensure' => 'absent',
            'modules' => [
              { 'module' => 'system', 'metricsets' => ['cpu', 'memory'], 'period' => '10s' },
              {
                'module' => 'apache',
                'metricsets' => ['status'],
                'period' => '10s',
                'hosts' => ['http://127.0.0.1'],
              },
            ],
            'outputs' => { 'elasticsearch' => { 'hosts' => ['http://localhost:9200'] } },
          }
        end

        it { is_expected.to compile }
      end

      context 'with multiple processors' do
        let(:params) do
          {
            'ensure' => 'absent',
            'modules' => [{ 'module' => 'system', 'metricsets' => ['cpu', 'memory'], 'period' => '10s' }],
            'outputs' => { 'elasticsearch' => { 'hosts' => ['http://localhost:9200'] } },
            'processors' => [
              { 'add_cloud_metadata' => { 'timeout' => '3s' } },
              { 'drop_fields' => { 'fields' => ['field1', 'field2'] } },
            ],
          }
        end

        it { is_expected.to compile }
      end
    end
  end
end
