import Component from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { action } from "@ember/object";
import { inject as service } from "@ember/service"
import Group from "discourse/models/group";

export default class PrivateTopics extends Component {
  @service siteSettings;
  @tracked allGroups;
  @tracked allowedGroupIds = [];

  constructor() {
    super(...arguments);
    Group.findAll().then((groups) => {
      this.allGroups = groups;
    });
    this.allowedGroupIds = this.groupIds;
  }

  get groupIds() {
    var g = this.allowedGroupIds; // necessary to trigger getter rerender
    let groups = this.args.outletArgs.category.custom_fields.private_topics_allowed_groups || "";
    return groups.split(',').filter(Boolean).map(Number) || [];
  }

  @action setAllowedGroups(groupIds) {
    this.args.outletArgs.category.custom_fields.private_topics_allowed_groups = groupIds.join(',');
    this.allowedGroupIds = groupIds;
  }
};