/*
 * libedmnativehelper.so yerine gecer.
 *
 * Cihazin stok blob seti (ve elimizdeki tek referans kopyasi) bu kutuphaneyi
 * hic icermiyor. vendor/lib/hw/bluetooth.default.so ise BIND_NOW ile bagli ve
 * DT_NEEDED listesinde onu istiyor; dosya yoksa bionic yukleyici
 * bluetooth.default.so'yu hic acmaz, Bluetooth yigini sessizce olur.
 *
 * bluetooth.default.so'nun bu kutuphaneden cozemedigi TEK sembol:
 *
 *   c_isBTOutgoingCallEnabled
 *
 * Iki cagri yeri var (bta_ag_sco_open, bta_ag_sco_conn_open), ikisi de:
 *
 *     blx c_isBTOutgoingCallEnabled@plt
 *     cbz r0, <normal yol>
 *
 * yani 0 donusu "ozel yonlendirme yok" dalini secer. Ayni yapiyi paylasan
 * dosyalar (libseccameracore.so) ayni kutuphaneden baska semboller de istiyor
 * ama o dosyalar hicbir yerden yuklenmiyor (olu agirlik).
 *
 * NOT: libedmnativehelper.so'da baska sembol olsaydi bu shim yetersiz kalirdi.
 * bluetooth.default.so'nun 182 UND sembolunden 181'i diger kutuphanelerden
 * cozuluyor; yalnizca bu biri buradan bekleniyor. Bunu dogrulayan betik:
 * scripts/blob-fixup.sh
 */

int c_isBTOutgoingCallEnabled(void)
{
    return 0;
}
