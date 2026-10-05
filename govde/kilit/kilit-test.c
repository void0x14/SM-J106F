/* KILIT TESTI — libusb'e DOGRUDAN link eder (heimdall gibi).
 *
 * Neden C: Python ctypes libusb'i dlopen+dlsym ile acar; dlsym kendi
 * kutuphanesinde aradigi icin LD_PRELOAD devreye girmez. Gercek programlar
 * (heimdall) libusb'e link eder ve PLT uzerinden cagirir; interposition
 * orada calisir. Bu test o yolu taklit eder.
 *
 * Cihaza YAZMA YOK. Yalnizca libusb_reset_device cagrisi denenir.
 *
 * Derleme:
 *   gcc -o kilit-test kilit-test.c $(pkg-config --cflags --libs libusb-1.0)
 */

#include <libusb-1.0/libusb.h>
#include <stdio.h>
#include <stdlib.h>

int main(void)
{
    libusb_context *ctx = NULL;
    libusb_device **liste = NULL;
    libusb_device_handle *h = NULL;

    if (libusb_init(&ctx) != 0) { fprintf(stderr, "init hata\n"); return 2; }
    ssize_t n = libusb_get_device_list(ctx, &liste);

    libusb_device *hedef = NULL;
    for (ssize_t i = 0; i < n; i++) {
        struct libusb_device_descriptor d;
        if (libusb_get_device_descriptor(liste[i], &d) != 0) continue;
        if (d.idVendor == 0x04e8 && d.idProduct == 0x685d) { hedef = liste[i]; break; }
    }
    if (!hedef) { fprintf(stderr, "cihaz bulunamadi\n"); libusb_free_device_list(liste,1); libusb_exit(ctx); return 1; }

    if (libusb_open(hedef, &h) != 0) { fprintf(stderr, "open hata\n"); libusb_free_device_list(liste,1); libusb_exit(ctx); return 1; }

    printf("reset cagriliyor...\n");
    fflush(stdout);
    int r = libusb_reset_device(h);
    printf("libusb_reset_device dondu: %d\n", r);

    libusb_close(h);
    libusb_free_device_list(liste, 1);
    libusb_exit(ctx);
    return 0;
}
