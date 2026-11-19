# Jelajah Nusantara

Game petualangan co-op berburu harta bertema nusantara, dibangun di atas Godot 3D Multiplayer Template.

## Tahap 1: inti permainan

- **Darah dan tumbang:** 100 darah, divalidasi server. Saat habis pemain tumbang lalu bangkit di titik awal setelah 5 detik.
- **Serangan:** klik kiri memukul musuh di depan. Tangan kosong 10, Golok 20, Kapak 28, Pedang Besar 35.
- **Makanan:** Ayam Bakar memulihkan 30 darah (tombol <kbd>Q</kbd>, klik dua kali, atau klik kanan lalu Makan).
- **Babi hutan:** mengejar pemain, ancang-ancang, lalu menyeruduk (15 damage). Menabrak batu membuatnya pusing lebih lama. Muncul lagi 45 detik setelah mati.
- **Peti harta:** tekan <kbd>E</kbd> di dekat peti; isinya keluar sebagai item yang bisa diambil.
- **Zona Pantai:** enam peti dan enam babi hutan tersebar di pantai. Posisi diatur lewat Marker3D di `scenes/level/pantai.tscn` (`EnemySpawns` dan `ChestSpawns`).

## Tahap 2: ekonomi

- **Koin:** tiap pemain mulai dengan 20 koin. Peti memberi 10-25 koin kepada pembukanya, babi hutan 4-9 koin kepada pemukul terakhir. Jumlahnya tampil di HUD.
- **Pedagang:** tekan <kbd>E</kbd> di depan lapak untuk membuka jendela jual-beli. Harga beli = nilai item x 2, harga jual = nilai item. Semua transaksi divalidasi server (jarak, koin, isi tas).
- **Desa Pelabuhan:** rumah panggung, lapak pedagang, gerbang, dan dermaga di sekitar titik awal. Desa adalah zona aman: musuh tidak mengejar pemain di dalamnya.

Stok dan pengali harga diatur di node `Pedagang` (`scenes/level/desa.tscn`, skrip `scripts/world/merchant.gd`). Zona aman adalah node di grup `safe_zones` dengan metadata `radius`.

## Tahap 3: Candi, pusaka, dan simpan progres

- **Candi:** lorong di tebing utara (lurus dari gerbang desa) menuju pelataran candi, lorong jebakan duri, dan ruang pusaka.
- **Kera pencuri:** mencuri satu barang dari tas (atau sampai 15 koin bila tas kosong) lalu kabur. Kalahkan sebelum 9 detik untuk mendapatkannya kembali; kalau lolos, barangnya hilang.
- **Arca penjaga:** lambat, 180 darah, tidak terdorong saat dipukul. Mengangkat badan 1 detik lalu menghantam area di sekitarnya (30 damage); menjauhlah saat ia ancang-ancang.
- **Jebakan duri:** siklus diam, peringatan, naik (20 damage). Dua baris di lorong naik bergantian.
- **Keris Pusaka:** isi Peti Pusaka di ruang terdalam. Senjata terkuat (45 damage) dan laku 400 koin. Pembukaan petinya diumumkan ke semua pemain.
- **Simpan progres:** isi tas, barang terpasang, dan koin disimpan di server tiap 20 detik, saat pemain keluar, dan saat host menutup game. Berkasnya `user://jelajah_save.json` di komputer host; tiap pemain dikenali lewat token acak di `user://jelajah_profile.cfg` miliknya.

Jenis musuh dan isi peti diatur lewat metadata Marker3D di `EnemySpawns` dan `ChestSpawns` tiap zona (`enemy_type`, `guaranteed_item`, `loot_rolls`, `coins_min`, `coins_max`, `chest_scale`, `announce_name`). Semua musuh memakai `scripts/enemies/enemy.gd` dengan `behavior` berbeda.

Argumen baris perintah (setelah `--`): `--save-suffix=_nama` memakai berkas simpanan terpisah, `--no-save` mematikan simpan dan muat.

## Tahap 4: Hutan, Gunung, dan audio

- **Hutan Rimba:** lorong di tebing barat pantai. Jalur bercabang di antara pepohonan menuju peti, kawanan babi hutan, kera, dan sarang harimau yang menyimpan **Mahkota Pusaka** (topi, laku 350 koin). Pisang tergeletak di sepanjang jalur (memulihkan 15 darah).
- **Gunung Api:** gerbang di utara hutan. Tiga teras dihubungkan tanjakan, dengan kolam dan sungai lahar (12 damage tiap 0,6 detik) yang hanya aman diseberangi lewat jembatan batu. Di puncak, Raksasa Api (450 darah, hantaman 40) menjaga **Tombak Pusaka** (60 damage, laku 800 koin).
- **Harimau:** penyeruduk yang lebih cepat dan keras dari babi hutan (110 darah, terkaman 25).
- **Caping:** topi baru yang dijual pedagang dan dipakainya sendiri.
- **Audio:** 20 efek suara, 3 lagu gamelan (desa, jelajah, candi/gunung), dan 3 ambience (ombak, hutan, gunung api). Musik berganti sesuai zona. Volume musik dan efek diatur di menu pause.
- **Nama zona** tampil di atas layar.

Semua audio disintesis lewat skrip, tanpa aset luar. `scripts/autoload/audio_manager.gd` memutar efek saat tiap peer melihat perubahan yang memang sudah disinkronkan, jadi tidak ada RPC khusus suara. Kolam lahar memakai `scripts/world/lava_pool.gd`; item yang tergeletak sejak awal ditandai Marker3D di `ItemSpawns` (metadata `item_id`); waktu muncul ulang musuh bisa diatur per titik lewat metadata `respawn_seconds`.

File utama: `scripts/player/player.gd` (darah, serangan), `scripts/enemies/enemy.gd`, `scripts/world/chest.gd`, `scripts/ui/hud_ui.gd`, dan `scripts/autoload/item_database.gd` (daftar item beserta damage dan pemulihan).

### Tes otomatis

Semua tes dijalankan dengan `--save-suffix=_test` supaya simpanan asli tidak tersentuh:

```bash
godot --headless --path . -s tests/test_server.gd -- --save-suffix=_test
```

Ganti nama berkasnya dengan `test_trade.gd` (koin, pedagang, zona aman), `test_candi.gd` (kera, arca, jebakan, pusaka), `test_save.gd` (simpan progres), atau `test_zones.gd` (hutan, gunung, item baru, audio).

`tests/test_client.gd` menguji sinkronisasi jaringan: jalankan dulu `godot --headless --path . -- --save-suffix=_test` sebagai server, lalu tes ini di terminal lain dengan argumen yang sama.

---

Di bawah ini dokumentasi template aslinya.

# Godot 3D Multiplayer Template

Godot 4.7 starter project for building a 3D multiplayer game with player movement, sessions, inventory, equipment, chat, and dedicated-server support.

> This template is also available on the [Godot Asset Library](https://godotengine.org/asset-library/asset/3377) and [Godot Asset Store](https://store.godotengine.org/asset/devmoreir4/godot-3d-multiplayer-template/).

## Key Features

- **Multiplayer Sessions:** Host, join, test multiple local instances, or run a headless dedicated server with support for up to 10 players.
- **Character Controller:** Camera-relative movement, sprinting, double jumping, synchronized animations, and switchable first- and third-person views.
- **Player Profiles:** Four selectable character skins and in-world name tags for every player.
- **Chat and Player List:** Communicate with connected players and view the current session members.
- **Server-Authoritative Inventory:** 16 base slots, 4 backpack slots, stacking, drag and drop, context actions, and server-validated changes.
- **Synchronized Equipment:** Hats, weapons, and backpacks are visible on every player's character.
- **World Items:** Drop, push, and collect physics-based items.
- **Integrated Interfaces:** Inventory, chat, player list, and pause menu coordinate gameplay input and mouse capture.

## Project Structure

- `assets/`: Imported models, textures, icons, fonts, and third-party asset attribution files.
- `scenes/items/`: World-drop scenes organized into backpacks, hats, miscellaneous items, and weapons.
- `scenes/level/`: Main level, arena, and multiplayer player scenes.
- `scenes/ui/`: Inventory, menus, chat, and online-player-list scenes.
- `scripts/autoload/`: Global `Network` and `ItemDatabase` singletons.
- `scripts/inventory/`: Item data, inventory slots, and player inventory state.
- `scripts/items/`: World-item behavior.
- `scripts/level/`: Level and multiplayer session coordination.
- `scripts/player/`: Player controller, character model, and camera support.
- `scripts/ui/`: User-interface behavior.

## How to Run the Project

Follow these simple steps to get the template up and running:

1. **Clone or Download:** Obtain the repository by cloning it via Git or downloading the ZIP file.
2. **Open in Godot Engine:** Load the project in [Godot Engine 4.7](https://godotengine.org).
3. **Execute:** Press <kbd>F5</kbd> or click `Run Project` in the Godot editor.

For local multiplayer testing, open `Debug > Customize Run Instances`, enable `Enable Multiple Instances`, choose the desired number of instances, and run the project.

## Dedicated Server

From the project directory, start a headless server with:

```bash
godot --headless --path .
```

Then start another project instance, choose `Join`, and connect to `127.0.0.1`. The server listens on UDP port `8080`. Press <kbd>Ctrl</kbd>+<kbd>C</kbd> in the server terminal to stop it.

On Linux or macOS, the provided wrapper can also locate the Godot executable and handle shutdown:

```bash
./run_headless_server.sh
```

Ensure the script has execution permissions (`chmod +x run_headless_server.sh`) and that the `godot` binary is in your system `PATH`. If Godot is installed under another command or path, set `GODOT_BIN` when starting the server:

```bash
GODOT_BIN=/path/to/godot ./run_headless_server.sh
```

## Controls

- <kbd>W</kbd> <kbd>A</kbd> <kbd>S</kbd> <kbd>D</kbd> to move.
- <kbd>Shift</kbd> to run.
- <kbd>Space</kbd> to jump or double jump.
- Left mouse button to attack enemies in front of you.
- <kbd>E</kbd> to collect a nearby item or open a chest.
- <kbd>Q</kbd> to eat the first food item in the inventory.
- <kbd>Esc</kbd> to open or close the pause menu.
- <kbd>T</kbd> to hide/show chat.
- <kbd>I</kbd> to toggle inventory.
- Hold <kbd>Tab</kbd> to show the online player list.
- <kbd>V</kbd> to switch between first-person and third-person views.
- <kbd>F1</kbd> to add a random test item (debug builds, host only).
- <kbd>F2</kbd> to print the local inventory (debug).

## Contributing

If you want to contribute to this project, please refer to our [Contributing Guidelines](CONTRIBUTING.md).

## Credits

- 3D Godot Robot Platformer Character, by AGChow, licensed under CC0. See [`assets/characters/player/ATTRIBUTIONS.md`](assets/characters/player/ATTRIBUTIONS.md).
- Item models and icons by Poly by Google and Quaternius. See [`assets/items/ATTRIBUTIONS.md`](assets/items/ATTRIBUTIONS.md).
- Prototype environment textures by Kenney, licensed under CC0. See [`assets/environment/ATTRIBUTIONS.md`](assets/environment/ATTRIBUTIONS.md).

## License

The project source code is available under the [MIT License](LICENSE). Third-party assets are excluded from that license and remain available under the terms documented in their respective attribution files.
