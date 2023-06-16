# name: discourse-private-topics
# about: Communiteq private topics plugin
# version: 1.1
# authors: richard@communiteq.com
# url: https://github.com/communiteq/discourse-private-topics

enabled_site_setting :private_topics_enabled

module ::DiscoursePrivateTopics
  def DiscoursePrivateTopics.get_filtered_category_ids(user)
    return [] unless SiteSetting.private_topics_enabled

    # first get all the categories with private topics enabled
    cat_ids = CategoryCustomField.where(name: 'private_topics_enabled').where(value: 'true').pluck(:category_id).to_a
    # we need to initialize the hash in case there are categories without whitelisted groups, or if we're anonymous user
    cat_group_map = cat_ids.map { |i| [i, []] }.to_h

    # remove the categories that have a whitelisted group we're a member of
    if user
      # get the groups that are excluded from filtering for each category
      excluded_map = CategoryCustomField.
        where(category_id: cat_ids).
        where(name: 'private_topics_allowed_groups').
        each_with_object({}) do |record, h|
          h[record.category_id] = record.value.split(',').map(&:to_i)
        end
      cat_group_map.merge! (excluded_map)
      # compare them to the groups we're member of
      # so we end up with a list of category ids that we cannot see other peoples topics in

      user_group_ids = user.groups.pluck(:id).to_a
      cat_group_map = cat_group_map.reject { |k, v| (v & user_group_ids).any? }
    end

    filtered_category_ids = cat_group_map.keys
  end
end

after_initialize do
    # hide posts from search results
    module PrivateTopicsPatchSearch
      def execute(readonly_mode: @readonly_mode)
        super

        if SiteSetting.private_topics_enabled
          cat_ids = DiscoursePrivateTopics.get_filtered_category_ids(@guardian.user)
          unless cat_ids.empty?
            @results.posts.delete_if do |post|
              next false if post&.user&.id == @guardian.user&.id
              post&.topic&.category&.id && cat_ids.include?(post.topic.category&.id)
            end
          end
        end

        @results
      end
    end

  Site.preloaded_category_custom_fields << 'private_topics_enabled'
  Site.preloaded_category_custom_fields << 'private_topics_allowed_groups'

  class ::Search
    prepend PrivateTopicsPatchSearch
  end

  TopicQuery.add_custom_filter(:private_topics) do |result, query|
    if SiteSetting.private_topics_enabled
      cat_ids = DiscoursePrivateTopics.get_filtered_category_ids(query&.user).join(",")
      unless cat_ids.empty?
        if query.user
          result = result.where("(topics.category_id NOT IN (#{cat_ids}) OR topics.user_id = #{query.user.id})")
        else
          result = result.where("topics.category_id NOT IN (#{cat_ids})")
        end
      end
    end
    result
  end
end
