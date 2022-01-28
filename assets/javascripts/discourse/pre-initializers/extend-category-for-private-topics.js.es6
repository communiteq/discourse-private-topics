import Category from "discourse/models/category";
import { alias } from "@ember/object/computed";

export default {
  name: "extend-category-for-private-topics",
  before: "inject-discourse-objects",
  initialize() {
    Category.reopen({
      private_topics_enabled: Ember.computed(
        "custom_fields.private_topics_enabled",
        {
          get(fieldName) {
            return Ember.get(this.custom_fields, fieldName) === "true";
          },
        }
      ),
    });
  },
};
