import Component from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { action, computed } from "@ember/object";
import { inject as service } from "@ember/service"

export default class PrivateTopics extends Component {
  @service site;
  @service siteSettings;
  @tracked selectedGroups = null;

  constructor() {
    super(...arguments);
    let groupNames = [];
    let groupIds = (this.args.outletArgs.category.custom_fields.private_topics_allowed_groups || "").split(",").filter(Boolean).map(id => parseInt(id, 10));
    this.site.groups.forEach((group) => {
      if (groupIds.includes(parseInt(group.id,10))) {
        groupNames.push(group.name);
      }
    });
    this.selectedGroups = groupNames;
  }

  @computed("site.groups.[]")
  get availableGroups() {
    return (this.site.groups || [])
      .map((g) => { // don't list "everyone"
        return g.id === 0 ? null : g.name;
      })
      .filter(Boolean);
  }

  @action
  onChangeGroups(groupNames) {
    this.selectedGroups = groupNames;
   // let groupNames = values.split(",").filter(Boolean);
    let groupIds = [];
    this.site.groups.forEach((group) => {
      if (groupNames.includes(group.name)) {
        groupIds.push(group.id);
      }
    });
    this.args.outletArgs.category.custom_fields.private_topics_allowed_groups = groupIds.join(',');
  }
};