/*
 * libusb_reset_device KILIDI — 04e8:685d icin reset'i IMKANSIZ kilar.
 *
 * Neden: heimdall'in USB reset yamasi bu cihazda zarar veriyordu (olculdu:
 * 15 kez reset, cihaz oturumu kapandi, handshake zaman asimina ugradi).
 * Bu shim, libusb_reset_device cagrisini HEDEF cihaz icin yakalar ve
 * gercek reset'i HIC YAPMAZ; cagirana basarili (0) doner.
 *
 * Kaynak: LD_PRELOAD symbol interposition (dlsym RTLD_NEXT). Capraz
 * arastirildi: INDI/ZWO ASI kamera suruculeri icin ayni desen kullaniliyor.
 *
 * Kapsam: YALNIZCA 04e8:685d. Baska cihazlarin reset'i etkilenmez.
 *
 * Derleme:
 *   gcc -shared -fPIC -o libusb-reset-kilit.so libusb-reset-kilit.c \
 *       -ldl $(pkg-config --cflags libusb-1.0) -O2 -Wall
 */

#define _GNU_SOURCE
#include <dlfcn.h>
#include <libusb-1.0/libusb.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <unistd.h>

#define KILIT_VID 0x04e8
#define KILIT_PID 0x685d

static int (*gercek_reset)(libusb_device_handle *);
static int engellendi_sayaci = 0;

void baslat(void)
{
    /* libusb'e link etmeyen programlarda (ornegin /bin/true) dlsym bos doner;
       bu normaldir, hata basmayiz. heimdall link ettigi icin bulunur. */
    gercek_reset = dlsym(RTLD_NEXT, "libusb_reset_device");
}

/*
 * Kutuphane yuklenir yuklenmez bir kez calisir. Boylece interposition'in
 * devrede oldugu, libusb_reset_device cagrilmasa bile GORULUR (kanit).
 * Ayrica her calismada journald'a yazar: kilit kurulu mu, kim calistirdi.
 */
__attribute__((constructor))
static void yuklemede_bildir(void)
{
    fprintf(stderr, "libusb-reset-kilit: YUKLENDI pid=%d\n", (int)getpid());
    fprintf(stderr, "libusb-reset-kilit: aktif (04e8:685d reset EDILMEZ)\n");
    fflush(stderr);
    baslat();
}

int libusb_reset_device(libusb_device_handle *dev)
{
    static pthread_once_t bir_kez = PTHREAD_ONCE_INIT;
    pthread_once(&bir_kez, baslat);

    if (dev) {
        libusb_device *u = libusb_get_device(dev);
        if (u) {
            struct libusb_device_descriptor d;
            if (libusb_get_device_descriptor(u, &d) == 0
                && d.idVendor == KILIT_VID && d.idProduct == KILIT_PID) {
                engellendi_sayaci++;
                fprintf(stderr,
                    "libusb-reset-kilit: 04e8:685d reset ENGELLENDI (#%d)\n",
                    engellendi_sayaci);
                return LIBUSB_SUCCESS;   /* reset YAPILMADI */
            }
        }
    }

    if (!gercek_reset)
        return LIBUSB_ERROR_NOT_SUPPORTED;
    return gercek_reset(dev);
}
