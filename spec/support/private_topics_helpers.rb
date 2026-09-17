# frozen_string_literal: true

# Shared fabrication for the private topics specs.
#
# The plugin is driven by two category custom fields:
#
#   private_topics_enabled         "true" on a category that has private topics
#   private_topics_allowed_groups  comma separated group ids that are exempt from
#                                  the filtering, for that category only (their
#                                  members see everybody's topics)
#
# and by three site settings:
#
#   private_topics_enabled           master switch, default false
#   private_topics_permitted_groups  topics *started by* a member of these groups
#                                    are always shown (default "1" = admins), no
#                                    matter who is looking
#   private_topics_admin_sees_all    admins are never filtered, default true
module PrivateTopicsHelpers
  # A category with private topics switched on. Pass `allowed_groups` for the
  # per-category exemption list.
  def private_topics_category(allowed_groups: nil, **opts)
    category = Fabricate(:category, **opts)
    category.upsert_custom_fields("private_topics_enabled" => "true")

    if allowed_groups.present?
      ids = Array(allowed_groups).map(&:id).join(",")
      category.upsert_custom_fields("private_topics_allowed_groups" => ids)
    end

    category
  end

  # A topic (no posts) in a private category, authored by `user`.
  def private_topics_topic(user:, category: nil)
    Fabricate(:topic, user: user, category: category || private_topics_category)
  end

  # A group with `users` as members.
  def private_topics_group(*users)
    group = Fabricate(:group)
    users.each { |user| group.add(user) }
    group
  end
end

RSpec.configure { |config| config.include PrivateTopicsHelpers }
