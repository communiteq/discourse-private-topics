# frozen_string_literal: true

require "rails_helper"
require_relative "../support/private_topics_helpers"

# This plugin patches a lot of core behaviour. These specs guard the *mechanism*:
# every patch must be a `prepend`ed module so it chains with `super` (and so with
# other plugins, in any load order) and is re-applied after a code reload, rather
# than an `alias_method` copy of the original method.
#
# The aliases that used to be here are not theoretical: with discourse-pm-scanner
# installed (it prepends its own module to TopicGuardian), `alias_method
# :org_can_see_topic?, :can_see_topic?` copied *its* method instead of core's, and
# because an aliased method keeps the `super` of its original definition site, the
# two called each other until every can_see_topic? call raised SystemStackError.
describe DiscoursePrivateTopics do
  # A note on finding the modules: Discourse evaluates plugin.rb with instance_eval,
  # so `module PrivateTopicsPatchPost` inside it does *not* live under
  # DiscoursePrivateTopics - it lands in the plugin instance's own constant scope.
  # They are looked up by name in the ancestor chain they were prepended into,
  # which is where they matter anyway.
  def patch_module_in(ancestors, name)
    ancestors.find { |mod| mod.name&.end_with?(name) }
  end

  it "prepends an extension module for every patched core class" do
    expect(patch_module_in(Guardian.ancestors, "PrivateTopicsTopicGuardian")).to be_present
    expect(
      patch_module_in(Topic.singleton_class.ancestors, "PrivateTopicsTopicClassMethods"),
    ).to be_present
    expect(patch_module_in(Post.ancestors, "PrivateTopicsPatchPost")).to be_present
    expect(patch_module_in(Search.ancestors, "PrivateTopicsPatchSearch")).to be_present
    expect(
      patch_module_in(UserSummary.ancestors, "PrivateTopicsPatchUserSummary"),
    ).to be_present
    expect(
      patch_module_in(
        CategoryDetailedSerializer.ancestors,
        "PrivateTopicsPatchCategoryDetailedSerializer",
      ),
    ).to be_present
    expect(
      patch_module_in(UserAction.singleton_class.ancestors, "PrivateTopicsApplyCommonFilters"),
    ).to be_present
  end

  it "prepends the optional integration patches when those plugins are present" do
    if defined?(Follow::NotificationHandler)
      expect(
        patch_module_in(
          Follow::NotificationHandler.ancestors,
          "PrivateTopicsFollowNotificationHandler",
        ),
      ).to be_present
    end

    if defined?(DiscourseAi::Embeddings::SemanticSearch)
      expect(
        patch_module_in(
          DiscourseAi::Embeddings::SemanticSearch.ancestors,
          "PrivateTopicsDiscourseAiEmbeddingsSemanticSearch",
        ),
      ).to be_present
    end

    if defined?(DiscourseSolved::SolvedTopicsController)
      expect(
        patch_module_in(
          DiscourseSolved::SolvedTopicsController.ancestors,
          "PrivateTopicsDiscourseSolvedSolvedTopicsController",
        ),
      ).to be_present
    end
  end

  it "puts each extension ahead of the code it extends" do
    ancestors = Guardian.ancestors

    expect(
      ancestors.index(patch_module_in(ancestors, "PrivateTopicsTopicGuardian")),
    ).to be < ancestors.index(TopicGuardian)

    topic_class_ancestors = Topic.singleton_class.ancestors

    expect(
      topic_class_ancestors.index(
        patch_module_in(topic_class_ancestors, "PrivateTopicsTopicClassMethods"),
      ),
    ).to be < topic_class_ancestors.index(Topic.singleton_class)
  end

  it "leaves no alias_method copies behind" do
    expect(TopicGuardian.instance_methods).not_to include(:org_can_see_topic?)
    expect(Topic.singleton_class.instance_methods).not_to include(
      :original_for_digest_private_topics,
      :original_similar_to,
    )
  end

  it "chains to whatever runs after it instead of copying it" do
    # Look the module up rather than asking TopicGuardian which method it has:
    # the probe example below prepends to TopicGuardian and cannot be undone, so
    # `TopicGuardian.instance_method(:can_see_topic?).owner` depends on the order
    # examples happen to run in. Asking our own module is order-independent.
    guardian_module = patch_module_in(Guardian.ancestors, "PrivateTopicsTopicGuardian")

    expect(guardian_module.instance_method(:can_see_topic?).owner).to eq(guardian_module)
    expect(guardian_module.instance_methods(false)).to contain_exactly(:can_see_topic?)

    class_methods = patch_module_in(
      Topic.singleton_class.ancestors,
      "PrivateTopicsTopicClassMethods",
    )
    expect(class_methods.instance_methods(false)).to contain_exactly(
      :for_digest,
      :similar_to,
      :recent,
    )
  end

  it "survives another plugin prepending to TopicGuardian" do
    # Simulates discourse-pm-scanner (or any other plugin) prepending its own
    # can_see_topic? on top of us. With the old alias_method this was an infinite
    # loop; with prepend the chain is simply probe -> ours -> core.
    #
    # The probe is deliberately transparent (it only records that it ran and calls
    # super), so it is harmless for the rest of the suite even though RSpec cannot
    # un-prepend it - and that is exactly what the old code broke on, so it is
    # worth having a test for it.
    probe =
      Module.new do
        def can_see_topic?(topic, hide_deleted = true)
          @private_topics_probe_ran = true
          super
        end
      end

    ::TopicGuardian.prepend(probe)

    author = Fabricate(:user)
    viewer = Fabricate(:user)
    private_topic = private_topics_topic(user: author)

    SiteSetting.private_topics_enabled = true
    guardian = Guardian.new(viewer)

    expect { guardian.can_see_topic?(private_topic) }.not_to raise_error
    expect(guardian.instance_variable_get(:@private_topics_probe_ran)).to eq(true)
    # Both our filter (as a private category) and core (the topic is visible) ran.
    expect(guardian.can_see_topic?(private_topic)).to eq(false)

    SiteSetting.private_topics_enabled = false
    expect(guardian.can_see_topic?(private_topic)).to eq(true)
  end

  it "reaches core through super when the plugin has nothing of its own to add" do
    SiteSetting.private_topics_enabled = false

    author = Fabricate(:user)
    topic = Fabricate(:topic, user: author)

    expect(Guardian.new(Fabricate(:user)).can_see_topic?(topic)).to eq(true)
    expect(Topic.recent(5)).to include(topic)
    expect(Topic.similar_to(nil, nil)).to eq([])
  end
end
