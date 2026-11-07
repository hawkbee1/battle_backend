# battle_backend

[![style: very good analysis][very_good_analysis_badge]][very_good_analysis_link]
[![License: MIT][license_badge]][license_link]

The logic of the **Appwrite Functions around the battles** of Battle Team, a 3D, massive,
persistent, real-time team battle game (stack decision 8): each function of hawkbee's
`backend/functions` is a thin adapter around it.

- `Wars`: an admin creates a war, plans its battles and starts the next one, with its teams
  balanced by power; a player joins a war; an ended battle is carried over to the next.
- `Guilds`: guild requests between battles.
- `ApiKeys`: one key per account, shown once, stored hashed, revoked at once.
- `Rows`, the port of the Hawkbee database's tables, with `MemoryRows` and `AppwriteRows`;
  `Admins`, from the Appwrite label `btadmin`; `serve`, the answer of a function's execution.

The rules come from [battle_rules](https://github.com/hawkbee1/battle_rules), the rows and IDs
from hawkbee's `hawkbee_schema`.

## Part of hawkbee

This repository is a git submodule of the [hawkbee](https://github.com/hawkbee1/hawkbee)
monorepo and **only builds inside it** (pub workspace, `resolution: workspace`):

```sh
git clone --recurse-submodules https://github.com/hawkbee1/hawkbee.git
cd hawkbee && flutter pub get
```

The tests read the plan's data from that checkout. The tests on the local Appwrite are
opt-in: tag `appwrite`, with `APPWRITE_API_KEY` set (`dart_test.yaml`).

[license_badge]: https://img.shields.io/badge/license-MIT-blue.svg
[license_link]: https://opensource.org/licenses/MIT
[very_good_analysis_badge]: https://img.shields.io/badge/style-very_good_analysis-B22C89.svg
[very_good_analysis_link]: https://pub.dev/packages/very_good_analysis
