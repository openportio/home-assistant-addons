# Openport Home Assistant Add-ons

Reach your Home Assistant installation from anywhere through an
[openport.io](https://openport.io) tunnel — no port forwarding, no static IP,
no VPN setup.

## Installation

1. In Home Assistant, go to **Settings → Add-ons → Add-on Store**.
2. Open the ⋮ menu (top right) → **Repositories**.
3. Add this repository's URL and press **Add**.
4. Install the **Openport** add-on from the store.

Or click:

[![Add repository to Home Assistant](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2Fopenportio%2Fhome-assistant-addons)

## Add-ons

### [Openport](./openport)

Exposes your Home Assistant UI on a stable `https://<name>.u.openport.io`
address using an openport http-forward tunnel. WebSockets are fully supported,
so the Home Assistant frontend and the companion mobile apps work out of the
box.
