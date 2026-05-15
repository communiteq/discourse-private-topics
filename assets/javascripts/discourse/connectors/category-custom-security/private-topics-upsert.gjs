import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { action, computed, set } from "@ember/object";
import { service } from "@ember/service";
import { htmlSafe } from "@ember/template";
import { i18n } from "discourse-i18n";
import GroupChooser from "select-kit/components/group-chooser";

export default class PrivateTopicsUpsert extends Component {
  static shouldRender(args, context) {
    return context.siteSettings.enable_simplified_category_creation;
  }

  @service site;
  @service siteSettings;

  @tracked privateTopicsEnabledState = false;
  @tracked selectedGroups = null;
  @tracked permissions = this.args.outletArgs.category.permissions || [];

  isEnabledValue(value) {
    return value === "t" || value === true || value === "true";
  }

  get privateTopicsEnabled() {
    return this.privateTopicsEnabledState;
  }

  constructor() {
    super(...arguments);

    this.privateTopicsEnabledState =
      this.isEnabledValue(
        this.args.outletArgs.category.custom_fields?.private_topics_enabled
      );

    if (this.args.outletArgs.category.custom_fields) {
      this.args.outletArgs.category.custom_fields.private_topics_enabled =
        this.privateTopicsEnabledState ? "t" : "";
    }

    // Initialize selectedGroups from custom_fields
    let groupNames = [];
    let groupIds = (this.args.outletArgs.category.custom_fields?.private_topics_allowed_groups || "")
      .split(",")
      .filter(Boolean)
      .map((id) => parseInt(id, 10));

    this.site.groups.forEach((group) => {
      if (groupIds.includes(parseInt(group.id, 10))) {
        groupNames.push(group.name);
      }
    });
    this.selectedGroups = groupNames;
  }

  @computed("site.groups.[]")
  get availableGroups() {
    return (this.site.groups || [])
      .map((group) => {
        return group.id === 0 ? null : group.name;
      })
      .filter(Boolean);
  }

  @action
  async onTogglePrivateTopicsEnabled(_, { set: formSet, name }) {
    const value = this.privateTopicsEnabled ? "" : "t";
    this.privateTopicsEnabledState = value === "t";

    set(this.args.outletArgs.category.custom_fields, "private_topics_enabled", value);
    await formSet(name, value);
  }

  @action
  onChangeGroups(field, groupNames) {
    this.selectedGroups = groupNames;

    let groupIds = [];
    this.site.groups.forEach((group) => {
      if (groupNames.includes(group.name)) {
        groupIds.push(group.id);
      }
    });

    const value = groupIds.join(",");

    field.set(value);

    set(
      this.args.outletArgs.category.custom_fields,
      "private_topics_allowed_groups",
      value
    );
  }

  get showWarning() {
    if (this.privateTopicsEnabled) {
      let everyoneName = "everyone";
      this.site.groups.forEach((group) => {
        if (group.id === 0) {
          everyoneName = group.name;
        }
      });

      return this.permissions.some(
        (permission) => permission.group_name === everyoneName
      );
    }

    return false;
  }

  <template>
    {{#if this.siteSettings.private_topics_enabled}}
      {{#let @outletArgs.form as |form|}}
        <form.Section
          @title={{i18n "category.private_topics.title"}}
          class="category-custom-settings-outlet private-topics"
        >
          <form.Object @name="custom_fields" as |customFields|>
            <customFields.Field
              @name="private_topics_enabled"
              @title={{i18n "category.private_topics.enabled"}}
              @onSet={{this.onTogglePrivateTopicsEnabled}}
              @type="checkbox"
              as |field|
            >
              <field.Control checked={{this.privateTopicsEnabled}} />
            </customFields.Field>

            {{#if this.privateTopicsEnabled}}
              {{#if this.showWarning}}
                <section class="field">
                  <div class="alert alert-warning">
                    {{htmlSafe (i18n "category.private_topics.warning")}}
                  </div>
                </section>
              {{/if}}
              <customFields.Field
                @name="private_topics_allowed_groups"
                @title={{i18n "category.private_topics.allowed_groups_description"}}
                @type="custom"
                as |field|
              >
                <field.Control>
                  <GroupChooser
                    @content={{this.availableGroups}}
                    @valueProperty={{null}}
                    @nameProperty={{null}}
                    @value={{this.selectedGroups}}
                    @onChange={{fn this.onChangeGroups field}}
                  />
                </field.Control>
              </customFields.Field>
            {{/if}}
          </form.Object>
        </form.Section>
      {{/let}}
    {{/if}}
  </template>
}