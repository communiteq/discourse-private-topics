# name: discourse-private-topics
# about: Communiteq private topics plugin
# version: 1.1
# authors: richard@communiteq.com
# url: https://github.com/communiteq/discourse-private-topics

enabled_site_setting :private_topics_enabled

after_initialize do
  Site.preloaded_category_custom_fields << 'private_topics_enabled'
  Site.preloaded_category_custom_fields << 'private_topics_allowed_groups'
end
