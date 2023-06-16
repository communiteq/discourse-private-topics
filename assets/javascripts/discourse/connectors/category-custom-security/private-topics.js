import Group from "discourse/models/group";

export default {
  allGroups: null,
  allowedGroupIds: [],

  setupComponent(args, component) {
    Group.findAll().then((groups) => {
      this.set("allGroups", groups);
    });
    var groups = this.category.custom_fields.private_topics_allowed_groups || "";
    this.set("allowedGroupIds", groups.split(',').map(Number) || []);
  },
  actions: {
    setAllowedGroups(groupIds) {
      this.set("allowedGroupIds", groupIds);
      this.set("category.custom_fields.private_topics_allowed_groups", groupIds.join(','));
    },
    onChangeSetting(value) {
      this.set(
        "category.custom_fields.private_topics_enabled",
        value ? "true" : "false"
      );
    },
  },
};

