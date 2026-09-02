import Foundation

// MARK: Jerkgram v1.2D BUILD115_RESEARCH_STRINGS1
// Late legacy/research UI remains available, but its labels follow Telegram's
// selected language instead of carrying Russian literals in generated source.
public extension JerkgramStrings {
    private func researchText(_ english: String, _ russian: String) -> String {
        return self.languageCode == "ru" ? russian : english
    }

    var researchHiddenGiftsProbe: String {
        self.researchText("Hidden Gifts Direct Catalog Probe", "Проверка скрытых подарков")
    }
    var researchCheckNineGiftsSelf: String {
        self.researchText("Check 9 Gifts on This Account", "Проверить 9 подарков на себе")
    }
    var researchCheckUserGifts: String {
        self.researchText("Select User and Check", "Выбрать пользователя и проверить")
    }
    var researchHiddenGiftsSend: String {
        self.researchText("Hidden Gifts Send — Real Payment", "Hidden Gifts Send — реальное списание")
    }
    var researchSendToSelf: String {
        self.researchText("Send to Self", "Отправить себе")
    }
    var researchSelectAnotherRecipient: String {
        self.researchText("Select Another Recipient", "Выбрать другого получателя")
    }
    var researchHideSenderNameOn: String {
        self.researchText("Hide Sender Name: On", "Скрыть имя отправителя: Вкл")
    }
    var researchHideSenderNameOff: String {
        self.researchText("Hide Sender Name: Off", "Скрыть имя отправителя: Выкл")
    }
    var researchConfirmGiftRecipient: String {
        self.researchText("1. Confirm Gift and Recipient", "1. Подтвердить подарок и получателя")
    }
    var researchPayAndSend: String {
        self.researchText("2. SPEND 50 STARS AND SEND", "2. СПИСАТЬ 50 STARS И ОТПРАВИТЬ")
    }
    var researchResetSelection: String {
        self.researchText("Reset Selection", "Сбросить выбор")
    }
    var researchBotCapabilityHeader: String {
        self.researchText("Bot Account Capability Probe", "Проверка возможностей bot-аккаунта")
    }
    var researchBotCapability: String {
        self.researchText("Check Bot Account RPC", "Проверить RPC bot-аккаунта")
    }
    var researchBotDifference: String {
        self.researchText("Check updates.getDifference", "Проверить updates.getDifference")
    }
    var researchProfileIntelClipboard: String {
        self.researchText("Check Username from Clipboard", "Проверить username из буфера")
    }
    var researchProfileIntelSnapshot: String {
        self.researchText("Profile Snapshot + Photo History", "Снимок профиля + история фото")
    }
    var profileInformation: String {
        self.researchText("Profile Information", "Сведения профиля")
    }
    var showProfileInformation: String {
        self.researchText("Show Profile Information", "Показывать сведения")
    }
    var avatarDc: String {
        self.researchText("Avatar DC", "DC аватара")
    }
    var glassMaterialHint: String {
        self.researchText(
            "Glass changes only the interface material. Data, tabs, logging, and section heights do not depend on the effect. Reduced surfaces are used with Reduce Transparency and Low Power Mode.",
            "Glass меняет только материал интерфейса. Данные, вкладки, логирование и высота секций не зависят от эффекта. При Reduce Transparency и Low Power Mode используются облегчённые поверхности."
        )
    }
}
