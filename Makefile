include $(TOPDIR)/rules.mk

PKG_NAME:=norypt-privacy
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk

define Package/norypt-privacy
  SECTION:=net
  CATEGORY:=Network
  TITLE:=NORYPT Privacy -- Boot-time identity randomization for GL-XE3000
  DEPENDS:=+uqmi +kmod-usb-serial-option +usb-modeswitch +coreutils-shuf +bash
  URL:=https://github.com/dartonverhovan-ctrl/norypt-privacy
  PKGARCH:=all
endef

define Package/norypt-privacy/description
  Boot-time IMEI, Wi-Fi BSSID, and WAN MAC randomization for the
  GL-iNet Puli AX (GL-XE3000). Real OUI and TAC databases.
  Includes web panel at /norypt/, CLI, and sysupgrade persistence.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./src $(PKG_BUILD_DIR)/
endef

define Build/Compile
endef

define Package/norypt-privacy/install
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/src/init.d/norypt \
	               $(1)/etc/init.d/norypt

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/src/config/norypt \
	                $(1)/etc/config/norypt

	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/src/uci-defaults/99-norypt \
	               $(1)/etc/uci-defaults/99-norypt

	$(INSTALL_DIR) $(1)/etc/norypt
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/src/modules/detect_fw.sh  $(1)/etc/norypt/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/src/modules/luhn.sh        $(1)/etc/norypt/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/src/modules/random_mac.sh  $(1)/etc/norypt/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/src/modules/imei-random.sh $(1)/etc/norypt/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/src/modules/mac-random.sh  $(1)/etc/norypt/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/src/modules/wan-mac.sh     $(1)/etc/norypt/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/src/modules/log-wipe.sh    $(1)/etc/norypt/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/src/modules/cellular.sh    $(1)/etc/norypt/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/src/modules/run.sh         $(1)/etc/norypt/
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/src/db/tac.db             $(1)/etc/norypt/
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/src/db/oui-wifi.db        $(1)/etc/norypt/
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/src/db/oui-wan.db         $(1)/etc/norypt/

	$(INSTALL_DIR) $(1)/etc/hotplug.d/iface
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/src/hotplug.d/99-norypt-wan \
	               $(1)/etc/hotplug.d/iface/99-norypt-wan

	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/src/bin/norypt \
	               $(1)/usr/bin/norypt

	$(INSTALL_DIR) $(1)/www/cgi-bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/src/cgi-bin/norypt.cgi \
	               $(1)/www/cgi-bin/norypt.cgi

	$(INSTALL_DIR) $(1)/www/norypt
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/src/www/index.html $(1)/www/norypt/
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/src/www/style.css  $(1)/www/norypt/
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/src/www/app.js     $(1)/www/norypt/
endef

define Package/norypt-privacy/postinst
#!/bin/sh
[ "${IPKG_INSTROOT}" ] || /etc/init.d/norypt enable
# 99-norypt runs on first boot via uci-defaults, applying the uhttpd redirect;
# start the service now so IMEI/MAC randomization runs immediately after install
[ "${IPKG_INSTROOT}" ] || /etc/init.d/norypt start
grep -q '/etc/norypt/' /etc/sysupgrade.conf 2>/dev/null || cat >> /etc/sysupgrade.conf << 'SYSUPGRADE'
/etc/norypt/
/etc/config/norypt
/etc/init.d/norypt
/etc/uci-defaults/99-norypt
/etc/hotplug.d/iface/99-norypt-wan
/usr/bin/norypt
/www/cgi-bin/norypt.cgi
/www/norypt/
SYSUPGRADE
echo "NORYPT Privacy installed. Panel: http://192.168.8.1/norypt/"
endef

define Package/norypt-privacy/prerm
#!/bin/sh
/etc/init.d/norypt stop 2>/dev/null || true
/etc/init.d/norypt disable 2>/dev/null || true
endef

$(eval $(call BuildPackage,norypt-privacy))
