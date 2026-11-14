"""Appels Windows (ctypes) : fenêtre au premier plan, raccourci clavier, presse-papiers, fenêtres sans focus.

Rien n'est envoyé au jeu : on regarde seulement quelle fenêtre est devant, et on écoute un raccourci
enregistré auprès de Windows tant que WoW est au premier plan.
"""
import ctypes
import ctypes.wintypes as wt
import os
import threading
import time

from . import bande

user32 =ctypes.WinDLL("user32", use_last_error=True)
kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

GWL_EXSTYLE = -20
WS_EX_NOACTIVATE = 0x08000000
WS_EX_TOOLWINDOW = 0x00000080
WS_EX_APPWINDOW = 0x00040000
SWP_NOSIZE, SWP_NOMOVE, SWP_NOZORDER, SWP_NOACTIVATE, SWP_FRAMECHANGED = 0x1, 0x2, 0x4, 0x10, 0x20
MOD_ALT, MOD_CONTROL, MOD_SHIFT, MOD_WIN, MOD_NOREPEAT = 0x1, 0x2, 0x4, 0x8, 0x4000
WM_HOTKEY = 0x0312
PM_REMOVE = 0x1
PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
CF_UNICODETEXT = 13
GMEM_MOVEABLE = 0x0002

user32.GetForegroundWindow.restype = wt.HWND
user32.GetParent.argtypes = [wt.HWND]
user32.GetParent.restype = wt.HWND
user32.GetWindowThreadProcessId.argtypes = [wt.HWND, ctypes.POINTER(wt.DWORD)]
user32.GetWindowThreadProcessId.restype = wt.DWORD
user32.GetWindowLongPtrW.argtypes = [wt.HWND, ctypes.c_int]
user32.GetWindowLongPtrW.restype = ctypes.c_ssize_t
user32.SetWindowLongPtrW.argtypes = [wt.HWND, ctypes.c_int, ctypes.c_ssize_t]
user32.SetWindowLongPtrW.restype = ctypes.c_ssize_t
user32.SetWindowPos.argtypes = [wt.HWND, wt.HWND, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int, wt.UINT]
user32.SetForegroundWindow.argtypes = [wt.HWND]
user32.BringWindowToTop.argtypes = [wt.HWND]
user32.SetFocus.argtypes = [wt.HWND]
user32.AttachThreadInput.argtypes = [wt.DWORD, wt.DWORD, wt.BOOL]
user32.GetWindowRect.argtypes = [wt.HWND, ctypes.POINTER(wt.RECT)]
user32.IsWindow.argtypes = [wt.HWND]
user32.IsIconic.argtypes = [wt.HWND]
user32.RegisterHotKey.argtypes = [wt.HWND, ctypes.c_int, wt.UINT, wt.UINT]
user32.UnregisterHotKey.argtypes = [wt.HWND, ctypes.c_int]
user32.PeekMessageW.argtypes = [ctypes.POINTER(wt.MSG), wt.HWND, wt.UINT, wt.UINT, wt.UINT]
user32.OpenClipboard.argtypes = [wt.HWND]
user32.SetClipboardData.argtypes = [wt.UINT, wt.HANDLE]
user32.SetClipboardData.restype = wt.HANDLE
user32.GetClipboardData.argtypes = [wt.UINT]
user32.GetClipboardData.restype = wt.HANDLE
user32.GetClipboardOwner.restype = wt.HWND
user32.GetClipboardSequenceNumber.restype = wt.DWORD
user32.IsClipboardFormatAvailable.argtypes = [wt.UINT]
kernel32.OpenProcess.argtypes = [wt.DWORD, wt.BOOL, wt.DWORD]
kernel32.OpenProcess.restype = wt.HANDLE
kernel32.QueryFullProcessImageNameW.argtypes = [wt.HANDLE, wt.DWORD, wt.LPWSTR, ctypes.POINTER(wt.DWORD)]
kernel32.CloseHandle.argtypes = [wt.HANDLE]
kernel32.GetExitCodeProcess.argtypes = [wt.HANDLE, ctypes.POINTER(wt.DWORD)]
kernel32.GlobalAlloc.argtypes = [wt.UINT, ctypes.c_size_t]
kernel32.GlobalAlloc.restype = wt.HGLOBAL
kernel32.GlobalLock.argtypes = [wt.HGLOBAL]
kernel32.GlobalLock.restype = ctypes.c_void_p
kernel32.GlobalUnlock.argtypes = [wt.HGLOBAL]
kernel32.GlobalFree.argtypes = [wt.HGLOBAL]
kernel32.CreateMutexW.argtypes = [ctypes.c_void_p, wt.BOOL, wt.LPCWSTR]
kernel32.CreateMutexW.restype = wt.HANDLE

user32.GetDC.argtypes = [wt.HWND]
user32.GetDC.restype = wt.HDC
user32.ReleaseDC.argtypes = [wt.HWND, wt.HDC]
user32.ClientToScreen.argtypes = [wt.HWND, ctypes.POINTER(wt.POINT)]

gdi32 = ctypes.WinDLL("gdi32", use_last_error=True)
gdi32.CreateCompatibleDC.argtypes = [wt.HDC]
gdi32.CreateCompatibleDC.restype = wt.HDC
gdi32.CreateCompatibleBitmap.argtypes = [wt.HDC, ctypes.c_int, ctypes.c_int]
gdi32.CreateCompatibleBitmap.restype = wt.HBITMAP
gdi32.SelectObject.argtypes = [wt.HDC, wt.HGDIOBJ]
gdi32.SelectObject.restype = wt.HGDIOBJ
gdi32.BitBlt.argtypes = [wt.HDC, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int, wt.HDC, ctypes.c_int,
                         ctypes.c_int, wt.DWORD]
gdi32.GetDIBits.argtypes = [wt.HDC, wt.HBITMAP, wt.UINT, wt.UINT, ctypes.c_void_p, ctypes.c_void_p, wt.UINT]
gdi32.DeleteObject.argtypes = [wt.HGDIOBJ]
gdi32.DeleteDC.argtypes = [wt.HDC]
SRCCOPY = 0x00CC0020

EXES_WOW = {"wow.exe", "wowclassic.exe", "wow-64.exe", "wowt.exe", "wowb.exe"}


def rendre_net():
    """Coordonnées en vrais pixels sur les écrans à 125 % / 150 % (sinon tout est flou et décalé)."""
    try:
        ctypes.windll.shcore.SetProcessDpiAwareness(2)
    except (AttributeError, OSError):
        try:
            user32.SetProcessDPIAware()
        except (AttributeError, OSError):
            pass


def une_seule_instance(nom="PlatyplusTraducteur"):
    """False si le traducteur tourne déjà."""
    une_seule_instance.poignee = kernel32.CreateMutexW(None, False, nom)
    return ctypes.get_last_error() != 183  # ERROR_ALREADY_EXISTS


def hwnd_de(widget):
    """Poignée Windows d'une fenêtre tkinter (la vraie fenêtre, pas la zone intérieure)."""
    widget.update_idletasks()
    return user32.GetParent(widget.winfo_id()) or widget.winfo_id()


def sans_focus(widget):
    """Cliquer dans la fenêtre ne prend pas le clavier au jeu ; pas de bouton dans la barre des tâches."""
    hwnd = hwnd_de(widget)
    style = user32.GetWindowLongPtrW(hwnd, GWL_EXSTYLE)
    style = (style | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW) & ~WS_EX_APPWINDOW
    user32.SetWindowLongPtrW(hwnd, GWL_EXSTYLE, style)
    user32.SetWindowPos(hwnd, None, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED)


def coins_arrondis(widget):
    """Coins arrondis de Windows 11 (sans effet sur Windows 10)."""
    try:
        valeur = ctypes.c_int(2)  # DWMWCP_ROUND
        ctypes.windll.dwmapi.DwmSetWindowAttribute(hwnd_de(widget), 33, ctypes.byref(valeur), ctypes.sizeof(valeur))
    except (AttributeError, OSError):
        pass


def fenetre_devant():
    return user32.GetForegroundWindow()


_exe_par_pid = {}


def exe_de(hwnd):
    if not hwnd:
        return ""
    pid = wt.DWORD()
    user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
    if pid.value in _exe_par_pid:
        return _exe_par_pid[pid.value]
    nom = ""
    h = kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid.value)
    if h:
        try:
            tampon = ctypes.create_unicode_buffer(1024)
            taille = wt.DWORD(1024)
            if kernel32.QueryFullProcessImageNameW(h, 0, tampon, ctypes.byref(taille)):
                nom = os.path.basename(tampon.value).lower()
        finally:
            kernel32.CloseHandle(h)
    if len(_exe_par_pid) > 200:
        _exe_par_pid.clear()
    _exe_par_pid[pid.value] = nom
    return nom


def est_wow(hwnd):
    return exe_de(hwnd) in EXES_WOW


def rectangle(hwnd):
    r = wt.RECT()
    if hwnd and user32.IsWindow(hwnd) and not user32.IsIconic(hwnd) and user32.GetWindowRect(hwnd, ctypes.byref(r)):
        return r.left, r.top, r.right, r.bottom
    return None


def mettre_devant(hwnd):
    """Donne le clavier à une fenêtre (la nôtre ou celle du jeu)."""
    if not hwnd:
        return
    devant = user32.GetForegroundWindow()
    moi = kernel32.GetCurrentThreadId()
    autre = user32.GetWindowThreadProcessId(devant, None) if devant else 0
    attache = bool(autre and autre != moi and user32.AttachThreadInput(moi, autre, True))
    try:
        user32.BringWindowToTop(hwnd)
        user32.SetForegroundWindow(hwnd)
        user32.SetFocus(hwnd)
    finally:
        if attache:
            user32.AttachThreadInput(moi, autre, False)


def _ouvrir_presse_papiers():
    for _ in range(10):  # le presse-papiers peut être occupé un instant par un autre programme
        if user32.OpenClipboard(None):
            return True
        time.sleep(0.02)
    return False


_mes_copies = set()  # numéros de presse-papiers de nos propres copies (à ne pas traduire)


def copier(texte):
    """Met le texte dans le presse-papiers de Windows (Ctrl+V dans le jeu)."""
    donnees = ctypes.create_unicode_buffer(texte)
    taille = ctypes.sizeof(donnees)
    if not _ouvrir_presse_papiers():
        return False
    try:
        user32.EmptyClipboard()
        h = kernel32.GlobalAlloc(GMEM_MOVEABLE, taille)
        if not h:
            return False
        p = kernel32.GlobalLock(h)
        ctypes.memmove(p, ctypes.addressof(donnees), taille)
        kernel32.GlobalUnlock(h)
        if not user32.SetClipboardData(CF_UNICODETEXT, h):
            kernel32.GlobalFree(h)
            return False
        return True
    finally:
        user32.CloseClipboard()
        _mes_copies.add(user32.GetClipboardSequenceNumber())


def lire_presse_papiers():
    """Texte du presse-papiers, ou None."""
    if not user32.IsClipboardFormatAvailable(CF_UNICODETEXT) or not _ouvrir_presse_papiers():
        return None
    try:
        h = user32.GetClipboardData(CF_UNICODETEXT)
        if not h:
            return None
        p = kernel32.GlobalLock(h)
        if not p:
            return None
        try:
            return ctypes.wstring_at(p)
        finally:
            kernel32.GlobalUnlock(h)
    finally:
        user32.CloseClipboard()


# ----------------------------------------------------------------------------
# Capture d'un coin de l'écran (lecture seule)
# ----------------------------------------------------------------------------
class _BITMAPINFOHEADER(ctypes.Structure):
    _fields_ = [("biSize", wt.DWORD), ("biWidth", wt.LONG), ("biHeight", wt.LONG), ("biPlanes", wt.WORD),
                ("biBitCount", wt.WORD), ("biCompression", wt.DWORD), ("biSizeImage", wt.DWORD),
                ("biXPelsPerMeter", wt.LONG), ("biYPelsPerMeter", wt.LONG), ("biClrUsed", wt.DWORD),
                ("biClrImportant", wt.DWORD)]


def capturer(x, y, largeur, hauteur):
    """Pixels de l'écran (BGRA, de haut en bas), ou None. Sans CAPTUREBLT : nos fenêtres transparentes
    (la fenêtre des traductions) ne sont pas dans l'image, seulement ce que le jeu dessine dessous."""
    ecran = user32.GetDC(None)
    if not ecran:
        return None
    mem = gdi32.CreateCompatibleDC(ecran)
    bmp = gdi32.CreateCompatibleBitmap(ecran, largeur, hauteur)
    ancien = gdi32.SelectObject(mem, bmp)
    try:
        if not gdi32.BitBlt(mem, 0, 0, largeur, hauteur, ecran, x, y, SRCCOPY):
            return None
        info = _BITMAPINFOHEADER(ctypes.sizeof(_BITMAPINFOHEADER), largeur, -hauteur, 1, 32, 0, 0, 0, 0, 0, 0)
        tampon = ctypes.create_string_buffer(largeur * hauteur * 4)
        if not gdi32.GetDIBits(mem, bmp, 0, hauteur, tampon, ctypes.byref(info), 0):
            return None
        return tampon.raw
    finally:
        gdi32.SelectObject(mem, ancien)
        gdi32.DeleteObject(bmp)
        gdi32.DeleteDC(mem)
        user32.ReleaseDC(None, ecran)


def coin_du_jeu(hwnd):
    """Position à l'écran du coin haut-gauche de l'image du jeu (sa zone cliente)."""
    p = wt.POINT(0, 0)
    if hwnd and user32.ClientToScreen(hwnd, ctypes.byref(p)):
        return p.x, p.y
    return None


# ----------------------------------------------------------------------------
# Raccourci clavier
# ----------------------------------------------------------------------------
TOUCHES = {
    "entree": 0x0D, "entrée": 0x0D, "enter": 0x0D, "return": 0x0D, "espace": 0x20, "space": 0x20,
    "tab": 0x09, "inser": 0x2D, "insert": 0x2D, "pause": 0x13, "fin": 0x23, "end": 0x23,
    "debut": 0x24, "début": 0x24, "home": 0x24, "²": 0xDE,
}
MODIFICATEURS = {"ctrl": MOD_CONTROL, "control": MOD_CONTROL, "alt": MOD_ALT, "maj": MOD_SHIFT, "shift": MOD_SHIFT, "win": MOD_WIN}


def lire_raccourci(texte):
    """« ctrl+entree » -> (MOD_CONTROL, 0x0D). None si illisible."""
    mods, vk = 0, None
    for morceau in texte.lower().replace(" ", "").split("+"):
        if morceau in MODIFICATEURS:
            mods |= MODIFICATEURS[morceau]
        elif morceau in TOUCHES:
            vk = TOUCHES[morceau]
        elif len(morceau) == 1 and morceau.isalnum():
            vk = ord(morceau.upper())
        elif morceau.startswith("f") and morceau[1:].isdigit() and 1 <= int(morceau[1:]) <= 24:
            vk = 0x6F + int(morceau[1:])
        else:
            return None
    return (mods, vk) if vk else None


class Surveillance(threading.Thread):
    """Regarde 10 fois par seconde quelle fenêtre est devant.

    - prevenir(« devant », info) quand ça change (WoW, nous, autre) ;
    - le raccourci n'existe que pendant que WoW est devant : il ne gêne aucun autre programme ;
    - prevenir(« raccourci », hwnd_wow) quand il est pressé ;
    - prevenir(« copie », texte) quand on copie du texte dans le jeu (Ctrl+C dans la zone du clic droit sur [FR]),
      ou quand Platyplus montre la bande de pixels d'un clic sur [FR] (en haut à gauche de l'image du jeu).
    """

    def __init__(self, raccourci, prevenir, nos_fenetres, diagnostic=None):
        super().__init__(daemon=True)
        self.raccourci = raccourci      # (mods, vk) ou None
        self.prevenir = prevenir
        self.nos_fenetres = nos_fenetres  # fonction -> ensemble des hwnd du traducteur
        self.diagnostic = diagnostic      # dossier où garder les bandes illisibles (ou None)
        self.arret = threading.Event()
        self.hwnd_wow = None
        self.pid_wow = 0
        self.wow_vu = False
        self.derniere_bande = (None, 0.0)  # (numéro, heure) : la bande reste 0,6 s, on ne la lit qu'une fois
        self.dernier_diagnostic = 0.0
        self.bandes_lues = 0

    def run(self):
        # une erreur ne doit jamais arrêter la surveillance (raccourci, bande, visibilité) : on la note et on continue
        while not self.arret.is_set():
            try:
                self._boucle()
            except Exception:
                self._noter_erreur()
                time.sleep(1)

    def _noter_erreur(self):
        import traceback
        if not self.diagnostic:
            return
        try:
            os.makedirs(self.diagnostic, exist_ok=True)
            with open(os.path.join(self.diagnostic, "surveillance.log"), "a", encoding="utf-8") as f:
                f.write(time.strftime("--- %H:%M:%S ---\n") + traceback.format_exc())
        except OSError:
            pass

    def _boucle(self):
        msg = wt.MSG()
        actif = False
        dernier = None
        numero = user32.GetClipboardSequenceNumber()
        while not self.arret.is_set():
            n = user32.GetClipboardSequenceNumber()
            if n != numero:
                numero = n
                self._copie(n)
            devant = user32.GetForegroundWindow()
            if devant and est_wow(devant):
                etat = "wow"
                if devant != self.hwnd_wow:
                    pid = wt.DWORD()
                    user32.GetWindowThreadProcessId(devant, ctypes.byref(pid))
                    self.pid_wow = pid.value
                self.hwnd_wow = devant
                self.wow_vu = True
            elif devant and devant in self.nos_fenetres():
                etat = "nous"
            else:
                etat = "autre"
            if self.hwnd_wow and not user32.IsWindow(self.hwnd_wow):
                self.hwnd_wow = None
            if etat != dernier:
                dernier = etat
                self.prevenir("devant", etat)
            try:
                if self.raccourci:
                    if etat == "wow" and not actif:
                        actif = bool(user32.RegisterHotKey(None, 1, self.raccourci[0] | MOD_NOREPEAT, self.raccourci[1]))
                    elif etat != "wow" and actif:
                        user32.UnregisterHotKey(None, 1)
                        actif = False
                while user32.PeekMessageW(ctypes.byref(msg), None, 0, 0, PM_REMOVE):
                    if msg.message == WM_HOTKEY:
                        self.prevenir("raccourci", self.hwnd_wow)
                if etat == "wow":
                    try:
                        self._regarder_bande(devant)
                    except Exception:
                        self._noter_erreur()
                time.sleep(0.1 if actif or etat != "wow" else 0.05)
            except BaseException:
                if actif:
                    user32.UnregisterHotKey(None, 1)
                raise
        if actif:
            user32.UnregisterHotKey(None, 1)

    def _regarder_bande(self, hwnd):
        """Un clic sur [FR] ? Platyplus dessine alors une bande de pixels en haut à gauche (voir bande.py).
        On ne regarde qu'un tout petit coin (40 x 16 pixels) tant qu'elle n'est pas là."""
        coin = coin_du_jeu(hwnd)
        if coin is None:
            return
        x, y = coin
        brut = capturer(x, y, bande.LARGEUR_GUET, bande.HAUTEUR_GUET)
        if brut is None:
            return
        petit = bande.Image(brut, bande.LARGEUR_GUET, bande.HAUTEUR_GUET)
        if not bande.balise(petit):
            if bande.suspect(petit):
                self._garder("pas de balise", brut, bande.LARGEUR_GUET, bande.HAUTEUR_GUET)
            return
        brut = capturer(x, y, bande.LARGEUR_MAX, bande.HAUTEUR_MAX)
        if brut is None:
            return
        raison = []
        lu = bande.lire(bande.Image(brut, bande.LARGEUR_MAX, bande.HAUTEUR_MAX), raison)
        if not lu:
            self._garder(raison[0] if raison else "?", brut, bande.LARGEUR_MAX, bande.HAUTEUR_MAX)
            return  # on relira au tour suivant (la bande reste 0,6 s)
        numero, texte = lu
        ancien, quand = self.derniere_bande
        if numero == ancien and time.time() - quand < 3:
            return
        self.derniere_bande = (numero, time.time())
        self.bandes_lues += 1
        self.prevenir("copie", texte)

    def _garder(self, raison, brut, largeur, hauteur):
        """Bande vue mais illisible : capture gardée dans diagnostic\\ (une toutes les 2 s, 12 au plus)."""
        if not self.diagnostic or time.time() - self.dernier_diagnostic < 2:
            return
        self.dernier_diagnostic = time.time()
        try:
            os.makedirs(self.diagnostic, exist_ok=True)
            fichiers = sorted(f for f in os.listdir(self.diagnostic) if f.endswith(".bgra"))
            for ancien in fichiers[:max(0, len(fichiers) - 11)]:
                os.remove(os.path.join(self.diagnostic, ancien))
            nom = time.strftime("bande_%H%M%S") + f"_{largeur}x{hauteur}.bgra"
            with open(os.path.join(self.diagnostic, nom), "wb") as f:
                f.write(brut)
            with open(os.path.join(self.diagnostic, "bande.log"), "a", encoding="utf-8") as f:
                f.write(f"{time.strftime('%H:%M:%S')} {nom} : {raison}\n")
        except OSError:
            pass

    def _copie(self, numero):
        """Le presse-papiers a changé : si c'est une copie faite dans le jeu, la transmettre."""
        if numero in _mes_copies:
            _mes_copies.discard(numero)
            return
        proprietaire = user32.GetClipboardOwner()
        if proprietaire:
            du_jeu = est_wow(proprietaire)
        else:  # copie sans fenêtre propriétaire : on regarde qui est devant
            du_jeu = est_wow(user32.GetForegroundWindow())
        if not du_jeu:
            return
        texte = lire_presse_papiers()
        if texte:
            self.prevenir("copie", texte)

    def wow_tourne(self):
        """Le jeu tourne encore ? On regarde son processus (pas seulement sa fenêtre, qui peut changer)."""
        if self.pid_wow:
            h = kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, self.pid_wow)
            if h:
                try:
                    code = wt.DWORD()
                    if kernel32.GetExitCodeProcess(h, ctypes.byref(code)):
                        return code.value == 259  # STILL_ACTIVE
                finally:
                    kernel32.CloseHandle(h)
            return False
        return bool(self.hwnd_wow and user32.IsWindow(self.hwnd_wow))
