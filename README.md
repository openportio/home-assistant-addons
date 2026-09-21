# Openport Home Assistant Add-ons

Reach your Home Assistant installation from anywhere through an
[openport.io](https://openport.io) tunnel — no port forwarding, no static IP,
no VPN setup.

## Installation

1. In Home Assistant, go to **Settings → Apps** (apps were formerly called
   add-ons) and select **Install app**.
2. In the top-right corner, open the ⋮ menu → **Repositories**.
3. Add this repository's URL and select **Add**.
4. Install the **Openport** app from the new repository card.

Or click:

[![Add repository to Home Assistant](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2Fopenportio%2Fhome-assistant-addons)

## Apps

### [Openport](./openport)

Exposes your Home Assistant UI on a stable `https://<name>.u.openport.io`
address using an openport http-forward tunnel. WebSockets are fully supported,
so the Home Assistant frontend and the companion mobile apps work out of the
box.
