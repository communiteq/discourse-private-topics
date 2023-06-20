# name: discourse-private-topics
# about: Communiteq private topics plugin
# version: 1.4b
# authors: richard@communiteq.com
# url: https://github.com/communiteq/discourse-private-topics

enabled_site_setting :private_topics_enabled

module ::DiscoursePrivateTopics
  # gets a list of user ids we should always show topics for
  def DiscoursePrivateTopics.get_unfiltered_user_ids(user)
    user_ids = [ Discourse.system_user.id ]
    user_ids.append user.id if user && !user.anonymous?
    group_ids = SiteSetting.private_topics_permitted_groups.split("|").map(&:to_i)
    user_ids = user_ids + Group.where(id: group_ids).joins(:users).pluck('users.id')
    user_ids.uniq
  end

  # gets a list of category ids we should not show topics for (unless the user is unfiltered)
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
  # hide topics from search results
  module PrivateTopicsPatchSearch
    def execute(readonly_mode: @readonly_mode)
      super

      if SiteSetting.private_topics_enabled && !(SiteSetting.private_topics_admin_sees_all & @guardian&.user&.admin?)
        cat_ids = DiscoursePrivateTopics.get_filtered_category_ids(@guardian.user)
        unless cat_ids.empty?
          user_ids = DiscoursePrivateTopics.get_unfiltered_user_ids(@guardian.user)
          @results.posts.delete_if do |post|
            next false if user_ids.include? post&.user&.id
            post&.topic&.category&.id && cat_ids.include?(post.topic.category&.id)
          end
        end
      end

      @results
    end
  end

  # hide topics on from post stream and raw
  module ::TopicGuardian
    alias_method :org_can_see_topic?, :can_see_topic?

    def can_see_topic?(topic, hide_deleted = true)
      allowed = org_can_see_topic?(topic, hide_deleted)
      return false unless allowed # false stays false

      if SiteSetting.private_topics_enabled && !(SiteSetting.private_topics_admin_sees_all & @user&.admin?)
        return true unless topic&.category # skip for PM's

        user_ids = DiscoursePrivateTopics.get_unfiltered_user_ids(@user)
        return true if user_ids.include?(topic&.user&.id) # topic authors and permitted users are always good

        cat_ids = DiscoursePrivateTopics.get_filtered_category_ids(@user)
        return true if cat_ids.empty?

        return false if cat_ids.include?(topic.category&.id)
      end

      true
    end
  end

  # hide topics from user profile -> activity
  class ::UserAction
    module PrivateTopicsApplyCommonFilters
      def apply_common_filters(builder, user_id, guardian, ignore_private_messages=false)
        if SiteSetting.private_topics_enabled && !(SiteSetting.private_topics_admin_sees_all & guardian&.user&.admin?)
          cat_ids = DiscoursePrivateTopics.get_filtered_category_ids(guardian.user).join(",")
          unless cat_ids.empty?
            user_ids = DiscoursePrivateTopics.get_unfiltered_user_ids(guardian.user).join(",")
            builder.where("(t.category_id NOT IN (#{cat_ids}) OR p.user_id IN (#{user_ids}))")
          end
        end
        super(builder, user_id, guardian, ignore_private_messages)
      end
    end
    singleton_class.prepend PrivateTopicsApplyCommonFilters
  end

  # hide topics from user profile -> summary
  module PrivateTopicsPatchUserSummary
    def filtered_category_ids
      @cat_ids ||= DiscoursePrivateTopics.get_filtered_category_ids(@guardian&.user).join(",")
    end

    def unfiltered_user_ids
      @user_ids ||= DiscoursePrivateTopics.get_unfiltered_user_ids(@guardian&.user).join(",")
    end

    def topics
      if SiteSetting.private_topics_enabled && !(SiteSetting.private_topics_admin_sees_all & @guardian&.user&.admin?) && !filtered_category_ids.empty?
        return super.where("(topics.category_id NOT IN (#{filtered_category_ids}) OR topics.user_id IN (#{unfiltered_user_ids}))")
      end

      super
    end

    def replies
      if SiteSetting.private_topics_enabled && !(SiteSetting.private_topics_admin_sees_all & @guardian&.user&.admin?) && !filtered_category_ids.empty?
        return super.where("(topics.category_id NOT IN (#{filtered_category_ids}) OR topics.user_id IN (#{unfiltered_user_ids}))")
      end

      super
    end

    def links
      if SiteSetting.private_topics_enabled && !(SiteSetting.private_topics_admin_sees_all & @guardian&.user&.admin?) && !filtered_category_ids.empty?
        return super.where("(topics.category_id NOT IN (#{filtered_category_ids}) OR topics.user_id IN (#{unfiltered_user_ids}))")
      end

      super
    end
  end

  # don't send follow plugin notifications for the entire category (regardless of whether a user can see)
  module PrivateTopicsFollowNotificationHandler
    def handle
      return if post&.topic&.category&.id && DiscoursePrivateTopics.get_filtered_category_ids.include?(post.topic.category.id)
      super
    end
  end

  Site.preloaded_category_custom_fields << 'private_topics_enabled'
  Site.preloaded_category_custom_fields << 'private_topics_allowed_groups'

  class ::Search
    prepend PrivateTopicsPatchSearch
  end

  class ::UserSummary
    prepend PrivateTopicsPatchUserSummary
  end

  if defined?(Follow::NotificationHandler)
    class ::Follow::NotificationHandler
      prepend PrivateTopicsFollowNotificationHandler
    end
  end

  # hide topics from topic lists
  TopicQuery.add_custom_filter(:private_topics) do |result, query|
    if SiteSetting.private_topics_enabled && ! (SiteSetting.private_topics_admin_sees_all && query&.guardian&.user&.admin?)
      cat_ids = DiscoursePrivateTopics.get_filtered_category_ids(query&.guardian&.user).join(",")
      unless cat_ids.empty?
        user_ids = DiscoursePrivateTopics.get_unfiltered_user_ids(query&.guardian&.user).join(",")
        result = result.where("(topics.category_id NOT IN (#{cat_ids}) OR topics.user_id IN (#{user_ids}))")
      end
    end
    result
  end
end
