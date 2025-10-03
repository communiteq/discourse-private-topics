import Component from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { Input } from "@ember/component";
import { action, computed } from "@ember/object";
import { service } from "@ember/service";
import { htmlSafe } from "@ember/template";
import { i18n } from "discourse-i18n";
import GroupChooser from "select-kit/components/group-chooser";

export default class PrivateTopics extends Component {
  @service site;
  @service siteSettings;

  @tracked selectedGroups = null;
  @tracked permissions = this.args.outletArgs.category.permissions;

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
    let groupIds = [];
    this.site.groups.forEach((group) => {
      if (groupNames.includes(group.name)) {
        groupIds.push(group.id);
      }
    });
    this.args.outletArgs.category.custom_fields.private_topics_allowed_groups = groupIds.join(',');
  }

  get showWarning() {
    if (this.args.outletArgs.category.custom_fields.private_topics_enabled) {
      let everyoneName = 'everyone';
      this.site.groups.forEach((g) => {
        if (g.id === 0) {
          everyoneName = g.name;
        }
      });
      return this.permissions.some(permission => permission.group_name === everyoneName);
    }

    return false;
  }

  <template>
    {{#if this.siteSettings.private_topics_enabled}}
      <section>
        <h3>{{i18n "category.private_topics.title"}}</h3>
      </section>
      <section class="field category_private_topics_enabled">
        <label>
          <Input
            @type="checkbox"
            @checked={{this.args.outletArgs.category.custom_fields.private_topics_enabled}}
          />
          {{i18n "category.private_topics.enabled"}}
        </label>
      </section>

      {{#if this.args.outletArgs.category.custom_fields.private_topics_enabled}}
        {{#if this.showWarning}}
          <section class="field">
            <div class="alert alert-warning">
              {{htmlSafe (i18n "category.private_topics.warning")}}
            </div>
          </section>
        {{/if}}
        <section class="field">
          <label>
            {{i18n "category.private_topics.allowed_groups_description"}}
          </label>
          <div class="value">
          <GroupChooser
            @content={{this.availableGroups}}
            @valueProperty={{null}}
            @nameProperty={{null}}
            @value={{this.selectedGroups}}
            @onChange={{this.onChangeGroups}}
          />
          </div>
        </section>
      {{/if}}
    {{/if}}
  </template>
};