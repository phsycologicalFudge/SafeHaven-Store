export const SEVEN_DAYS_SEC = 7 * 24 * 60 * 60;

export const CATEGORIES = {
  security:      "Security",
  productivity:  "Productivity",
  utilities:     "Utilities",
  communication: "Communication",
  entertainment: "Entertainment",
  finance:       "Finance",
  health:        "Health & Fitness",
  education:     "Education",
  tools:         "Tools",
  other:         "Other",
};

export const IMAGE_SLOTS = [
  "icon",
  "screenshot_1",
  "screenshot_2",
  "screenshot_3",
  "screenshot_4",
  "screenshot_5",
  "screenshot_6",
];

export const ALLOWED_IMAGE_TYPES = ["image/png", "image/jpeg", "image/webp"];

export const MAX_IMAGE_BYTES     = 2 * 1024 * 1024;

export const INDEX_KEY = "index.json";

export const CHANGELOG_KEY = "index_changelog.json";

export const apkKey     = (packageName, versionCode) => `apps/${packageName}/${versionCode}/app.apk`;

export const stagingKey = (packageName, versionCode) => `staging/${packageName}/${versionCode}/app.apk`;

export const imageKey   = (packageName, slot)        => `images/${packageName}/${slot}`;
