import Category from "discourse/models/category";
import { get, computed } from "@ember/object";

export default {
  name: "extend-category-for-private-topics",
  before: "inject-discourse-objects",
  initialize() {
    Category.reopen({
      private_topics_enabled: computed(
        "custom_fields.private_topics_enabled",
        {
          get(fieldName) {
            return get(this.custom_fields, fieldName) === "true";
          },
        }
      ),
    });
  },
};
