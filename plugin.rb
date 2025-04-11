# name: discourse-private-topics
# about: Allows to keep topics private to the topic creator and specific groups.
# version: 1.5.11
# authors: Communiteq
# meta_topic_id: 268646
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
    cat_ids = CategoryCustomField.where(name: 'private_topics_enabled').pluck(:category_id).to_a
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

  module PrivateTopicsPatchPost
    def self.prepended(base)
      base.scope :public_posts, -> {
        posts = base.joins(:topic).where("topics.archetype <> ?", Archetype.private_message)
        private_category_ids = CategoryCustomField.where(name: 'private_topics_enabled').pluck(:category_id).to_a
        if SiteSetting.private_topics_enabled && private_category_ids.any?
          posts.where.not("topics.category_id IN (?)", private_category_ids)
        else
          posts
        end
      }
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

  module PrivateTopicsPatchCategoryDetailedSerializer
    def include_displayable_topics?
      displayable_topics.present? && custom_fields['private_topics_enabled'] != 't'
    end
  end

  # don't send follow plugin notifications for the entire category (regardless of whether a user can see)
  module PrivateTopicsFollowNotificationHandler
    def handle
      return if post&.topic&.category&.id && DiscoursePrivateTopics.get_filtered_category_ids(nil).include?(post.topic.category&.id)
      super
    end
  end

  module PrivateTopicsDiscourseAiEmbeddingsSemanticSearch
    def search_for_topics(query, page = 1)
      if SiteSetting.private_topics_enabled
        posts = super
        filtered_posts = posts.reject { |post| !@guardian.can_see_topic?(post.topic) }
      else
        super
      end
    end
  end

  Site.preloaded_category_custom_fields << 'private_topics_enabled'
  Site.preloaded_category_custom_fields << 'private_topics_allowed_groups'

  # this removes the categories from the "recent topics" shown on the 404 page
  # called from ApplicationController.build_not_found_page
  # this is cached without a user so just pass nil and exclude every private category
  class ::Topic
    def self.recent(max = 10)
      cat_ids = DiscoursePrivateTopics.get_filtered_category_ids(nil).join(",")
      if cat_ids.empty?
        Topic.listable_topics.visible.secured.order("created_at desc").limit(max)
      else
        Topic.listable_topics.visible.secured.where("category_id NOT IN (#{cat_ids})").order("created_at desc").limit(max)
      end
    end
  end

  class ::Topic
    class << self
      alias_method :original_for_digest_private_topics, :for_digest

      def for_digest(user, since, opts = nil)
        topics = original_for_digest_private_topics(user, since, opts)
        filtered_category_ids ||= DiscoursePrivateTopics.get_filtered_category_ids(user).join(",")
        if SiteSetting.private_topics_enabled && !(SiteSetting.private_topics_admin_sees_all & user&.admin?) && !filtered_category_ids.empty?
          unfiltered_user_ids = DiscoursePrivateTopics.get_unfiltered_user_ids(user).join(",")
          return topics.where("(topics.category_id NOT IN (#{filtered_category_ids}) OR topics.user_id IN (#{unfiltered_user_ids}))")
        end
        topics
      end

      alias_method :original_similar_to, :similar_to

      def similar_to(title, raw, user = nil)
        similar_topics = original_similar_to(title, raw, user)
        filtered_category_ids ||= DiscoursePrivateTopics.get_filtered_category_ids(user)
        if SiteSetting.private_topics_enabled && !(SiteSetting.private_topics_admin_sees_all & user&.admin?) && !filtered_category_ids.empty?
          filtered_topics = similar_topics.where.not(category_id: filtered_category_ids)
          filtered_topics = filtered_topics.or(similar_topics.where(user_id: user.id)) if user.present?
          return filtered_topics
        end
        similar_topics
      end
    end
  end

  class ::Post
    prepend PrivateTopicsPatchPost
  end

  class ::Search
    prepend PrivateTopicsPatchSearch
  end

  class ::UserSummary
    prepend PrivateTopicsPatchUserSummary
  end

  class ::CategoryDetailedSerializer
    prepend PrivateTopicsPatchCategoryDetailedSerializer
  end

  if defined?(Follow::NotificationHandler)
    class ::Follow::NotificationHandler
      prepend PrivateTopicsFollowNotificationHandler
    end
  end

  if defined?(DiscourseAi::Embeddings::SemanticSearch)
    class ::DiscourseAi::Embeddings::SemanticSearch
      prepend PrivateTopicsDiscourseAiEmbeddingsSemanticSearch
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

  # prevent backlinks to show up in wrong places
  # https://meta.discourse.org/t/private-topics-plugin/268646/81

  register_modifier(:topic_view_link_counts) do |link_counts|
    begin
      if SiteSetting.private_topics_enabled
        cat_ids = DiscoursePrivateTopics.get_filtered_category_ids(nil)
        unless cat_ids.empty?
          # get all topic ids
          topic_ids = link_counts.values.flatten.map do |link|
            next unless link.is_a?(Hash) && link[:internal] && link[:url].is_a?(String)
            match = link[:url].match(%r{/t/[^/]+/(\d+)(?:/\d+)?})
            match[1].to_i if match
          end.compact.uniq

          # get all categories for these topics
          topic_category_map = Topic.where(id: topic_ids).pluck(:id, :category_id).to_h

          # filter the links
          link_counts.each do |post_id, links|
            link_counts[post_id] = links.reject do |link|
              next false unless link.is_a?(Hash) && link[:internal] && link[:url].is_a?(String)
              match = link[:url].match(%r{/t/[^/]+/(\d+)(?:/\d+)?})
              next false unless match
              topic_id = match[1].to_i
              cat_ids.include?(topic_category_map[topic_id])
            end
          end
          # remove any empty entries
          link_counts.delete_if { |_post_id, links| !links.is_a?(Array) || links.empty? }
        end
      end
    rescue => e
      Rails.logger.warn("topic_view_link_counts modifier failed: #{e.class} - #{e.message}")
    end
    link_counts
  end
end
