# Enable a modules.d file either via a custom source, custom template or default module template
# $config can be used to pass down parameters into an .erb template
#
# @param template_name
# [String] The name of the template to use for the modules.d file.
#
# @param config
# [Hash] The configuration for the modules.d file.
#
# @param source
# [String] The source of the modules.d file.
#
# @param content
# [String] The content of the modules.d file.
#
define metricbeat::modulesd (
  String           $template_name = $name,
  Hash             $config        = {},
  Optional[String] $source        = undef,
  Optional[String] $content       = undef,
) {
  # Use the default template as the source if non specified
  if ! $source and ! $content {
    $default_source = "puppet:///modules/metricbeat/${template_name}.yml"
  } elsif $source {
    $default_source = $source
  } else {
    $default_source = undef
  }
  file { "${metricbeat::config_dir}/modules.d/${template_name}.yml":
    ensure  => file,
    source  => $default_source,
    content => $content,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    require => Class['metricbeat::install'],
    notify  => Class['metricbeat::service'],
  }
}
