#!/usr/bin/env python3
"""Generate SharedCore/Resources/GeoData.json for on-device place classification.

Russian declensions are generated for nominative names. A few irregular
toponyms are listed by hand. Re-run from the repo root:

    python3 Scripts/generate_geodata.py
"""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "SharedCore" / "Resources" / "GeoData.json"

SIBILANT = set("гкхжчшщ")
SIBILANT_INSTR = set("гкхжчшщц")
MASC_INSTR_SOFT = set("жчшщц")
VOWELS = set("аеёиоуыэюя")


def decline(name: str) -> list[str]:
    """Return extra Russian inflected forms (not including the nominative)."""
    if not name or " " in name or any(ch.isdigit() for ch in name):
        return []
    if name.endswith("ия"):
        stem = name[:-2]
        return [stem + "ии", stem + "ию", stem + "ией"]
    if name.endswith("ья") or name.endswith("йя"):
        stem = name[:-1]
        return [stem + "и", stem + "е", stem + "ю", stem + "ей"]
    if name.endswith("а"):
        stem = name[:-1]
        if not stem:
            return []
        last = stem[-1]
        gen = stem + ("и" if last in SIBILANT else "ы")
        instr = stem + ("ей" if last in SIBILANT_INSTR else "ой")
        return [gen, stem + "е", stem + "у", instr]
    if name.endswith("й"):
        stem = name[:-1]
        return [stem + "я", stem + "е", stem + "ю", stem + "ем"]
    if name.endswith("ь"):
        return []
    if name[-1] in VOWELS:
        return []
    # Masculine consonant, including hyphenated names whose last part declines.
    last = name[-1]
    instr = name + ("ем" if last in MASC_INSTR_SOFT else "ом")
    return [name + "а", name + "е", name + "у", instr]


def clean(forms: list[str], primary: str) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []
    for form in forms:
        form = form.strip()
        if not form or form.casefold() == primary.casefold():
            continue
        key = form.casefold()
        if key in seen:
            continue
        seen.add(key)
        out.append(form)
    return out


countries: list[dict] = []
cities: list[dict] = []


def add_country(
    cid: str,
    ru: str,
    en: str,
    aliases: list[str] | None = None,
    case_aliases: list[str] | None = None,
    decline_name: bool = True,
    en_sensitive: bool = False,
) -> None:
    extra = list(aliases or [])
    if decline_name:
        extra.extend(decline(ru))
    countries.append(
        {
            "id": cid,
            "ru": ru,
            "en": en,
            "aliases": clean(extra, ru),
            "caseAliases": clean(list(case_aliases or []), ru),
            "enSensitive": en_sensitive,
        }
    )


def add_city(
    cid: str,
    country: str,
    ru: str,
    en: str,
    aliases: list[str] | None = None,
    case_aliases: list[str] | None = None,
    decline_name: bool = True,
    en_sensitive: bool = False,
) -> None:
    extra = list(aliases or [])
    if decline_name:
        extra.extend(decline(ru))
        for alias in aliases or []:
            if alias and all("а" <= ch.lower() <= "я" or ch in "ёЁ-" for ch in alias):
                extra.extend(decline(alias))
    cities.append(
        {
            "id": cid,
            "country": country,
            "ru": ru,
            "en": en,
            "aliases": clean(extra, ru),
            "caseAliases": clean(list(case_aliases or []), ru),
            "enSensitive": en_sensitive,
        }
    )


def build() -> None:
    # --- Countries ---
    add_country("ru", "Россия", "Russia", ["РФ", "Russian Federation"])
    add_country("ua", "Украина", "Ukraine")
    add_country("by", "Беларусь", "Belarus", ["Беларуси", "Белоруссия", "Белоруссии", "Белоруссию"], en_sensitive=False)
    add_country("ee", "Эстония", "Estonia")
    add_country("lv", "Латвия", "Latvia")
    add_country("lt", "Литва", "Lithuania", ["Литвы", "Литве", "Литву", "Литвой"])
    add_country("pl", "Польша", "Poland")
    add_country("de", "Германия", "Germany")
    add_country("cz", "Чехия", "Czechia", ["Czech Republic", "Чехия"])
    add_country("sk", "Словакия", "Slovakia")
    add_country("at", "Австрия", "Austria")
    add_country("ch", "Швейцария", "Switzerland")
    add_country("fr", "Франция", "France")
    add_country("es", "Испания", "Spain")
    add_country("it", "Италия", "Italy")
    add_country("pt", "Португалия", "Portugal")
    add_country(
        "nl",
        "Нидерланды",
        "Netherlands",
        ["Нидерландах", "Нидерландов", "Голландия", "Голландии", "Голландию", "Голландией", "Holland"],
        decline_name=False,
    )
    add_country("be", "Бельгия", "Belgium")
    add_country("lu", "Люксембург", "Luxembourg")
    add_country(
        "gb",
        "Великобритания",
        "United Kingdom",
        ["Англия", "Англии", "Англию", "Англией", "Британия", "Британии", "Британию", "Britain", "England", "Scotland", "Шотландия", "Шотландии", "Уэльс", "Уэльсе"],
        case_aliases=["UK"],
        en_sensitive=False,
    )
    add_country("ie", "Ирландия", "Ireland")
    add_country("is", "Исландия", "Iceland")
    add_country("no", "Норвегия", "Norway")
    add_country("se", "Швеция", "Sweden")
    add_country("fi", "Финляндия", "Finland")
    add_country("dk", "Дания", "Denmark")
    add_country("gr", "Греция", "Greece")
    add_country("tr", "Турция", "Turkey", ["Türkiye", "Türkiye"], case_aliases=["Turkey"], en_sensitive=True)
    add_country("cy", "Кипр", "Cyprus")
    add_country("mt", "Мальта", "Malta", ["Мальты", "Мальте", "Мальту", "Мальтой"])
    add_country("hr", "Хорватия", "Croatia")
    add_country("me", "Черногория", "Montenegro")
    add_country("rs", "Сербия", "Serbia")
    add_country("si", "Словения", "Slovenia")
    add_country(
        "ba",
        "Босния и Герцеговина",
        "Bosnia and Herzegovina",
        ["Босния", "Боснии", "Боснию", "Герцеговина", "Герцеговине", "Bosnia"],
        decline_name=False,
    )
    add_country("al", "Албания", "Albania")
    add_country("bg", "Болгария", "Bulgaria")
    add_country("ro", "Румыния", "Romania")
    add_country("hu", "Венгрия", "Hungary")
    add_country("md", "Молдова", "Moldova", ["Молдовы", "Молдове", "Молдову", "Молдовой", "Молдавия", "Молдавии"])
    add_country("ge", "Грузия", "Georgia", case_aliases=["Georgia"], en_sensitive=True)
    add_country("am", "Армения", "Armenia")
    add_country("az", "Азербайджан", "Azerbaijan")
    add_country("kz", "Казахстан", "Kazakhstan")
    add_country("uz", "Узбекистан", "Uzbekistan")
    add_country("kg", "Кыргызстан", "Kyrgyzstan", ["Киргизия", "Киргизии", "Киргизию"])
    add_country("tj", "Таджикистан", "Tajikistan")
    add_country("cn", "Китай", "China")
    add_country("jp", "Япония", "Japan")
    add_country(
        "kr",
        "Южная Корея",
        "South Korea",
        ["Корея", "Корее", "Кореи", "Корею", "Кореей", "Южной Кореи", "Южную Корею", "Korea"],
        decline_name=False,
    )
    add_country("tw", "Тайвань", "Taiwan", ["Тайваня", "Тайване", "Тайваню"])
    add_country("th", "Таиланд", "Thailand")
    add_country("vn", "Вьетнам", "Vietnam")
    add_country("kh", "Камбоджа", "Cambodia", ["Камбоджи", "Камбодже", "Камбоджу", "Камбоджей"])
    add_country("la", "Лаос", "Laos", ["Лаосе", "Лаоса"])
    add_country("my", "Малайзия", "Malaysia")
    add_country("sg", "Сингапур", "Singapore")
    add_country("id", "Индонезия", "Indonesia")
    add_country(
        "ph",
        "Филиппины",
        "Philippines",
        ["Филиппинах", "Филиппин", "Филиппинам"],
        decline_name=False,
    )
    add_country("in", "Индия", "India")
    add_country("lk", "Шри-Ланка", "Sri Lanka")
    add_country("np", "Непал", "Nepal", ["Непале", "Непала", "Непалу"])
    add_country(
        "mv",
        "Мальдивы",
        "Maldives",
        ["Мальдивах", "Мальдив", "Мальдивам"],
        decline_name=False,
    )
    add_country(
        "ae",
        "ОАЭ",
        "United Arab Emirates",
        ["Эмираты", "Эмиратах", "Эмиратов", "Emirates"],
        case_aliases=["UAE"],
        decline_name=False,
    )
    add_country("qa", "Катар", "Qatar", ["Катаре", "Катара"])
    add_country(
        "sa",
        "Саудовская Аравия",
        "Saudi Arabia",
        ["Саудовской Аравии", "Саудовскую Аравию", "Саудовская Аравия"],
        decline_name=False,
    )
    add_country("om", "Оман", "Oman", ["Омане", "Омана"])
    add_country("bh", "Бахрейн", "Bahrain", ["Бахрейне", "Бахрейна"])
    add_country("il", "Израиль", "Israel", ["Израиля", "Израиле", "Израилю", "Израилем"])
    add_country("jo", "Иордания", "Jordan", case_aliases=["Jordan"], en_sensitive=True)
    add_country("eg", "Египет", "Egypt")
    add_country("ma", "Марокко", "Morocco", decline_name=False)
    add_country("tn", "Тунис", "Tunisia", ["Туниса", "Тунисе", "Тунису"])
    add_country("za", "ЮАР", "South Africa", ["ЮАР"], case_aliases=["RSA"], decline_name=False)
    add_country("ke", "Кения", "Kenya")
    add_country("tz", "Танзания", "Tanzania")
    add_country("mu", "Маврикий", "Mauritius", ["Маврикии", "Маврикий", "Маврикия", "Маврикию"], decline_name=False)
    add_country(
        "sc",
        "Сейшелы",
        "Seychelles",
        ["Сейшелах", "Сейшел", "Сейшелам"],
        decline_name=False,
    )
    add_country("mx", "Мексика", "Mexico", ["Мексики", "Мексике", "Мексику", "Мексикой"])
    add_country(
        "us",
        "США",
        "United States",
        ["Америка", "Америке", "Америку", "Америки", "Америкой"],
        case_aliases=["USA"],
        decline_name=False,
        en_sensitive=False,
    )
    add_country("ca", "Канада", "Canada", ["Канады", "Канаде", "Канаду", "Канадой"])
    add_country("br", "Бразилия", "Brazil")
    add_country("ar", "Аргентина", "Argentina", ["Аргентины", "Аргентине", "Аргентину", "Аргентиной"])
    add_country("cl", "Чили", "Chile", decline_name=False)
    add_country("pe", "Перу", "Peru", decline_name=False)
    add_country("cu", "Куба", "Cuba", ["Кубы", "Кубе", "Кубу", "Кубой"])
    add_country("au", "Австралия", "Australia")
    add_country(
        "nz",
        "Новая Зеландия",
        "New Zealand",
        ["Новой Зеландии", "Новую Зеландию", "Зеландия", "Зеландии"],
        decline_name=False,
    )
    add_country("mc", "Монако", "Monaco", decline_name=False)
    add_country("ad", "Андорра", "Andorra", ["Андорры", "Андорре", "Андорру", "Андоррой"])
    add_country("mn", "Монголия", "Mongolia")
    add_country("cr", "Коста-Рика", "Costa Rica")

    # --- Cities ---
    # Russia
    add_city("moscow", "ru", "Москва", "Moscow")
    add_city(
        "spb",
        "ru",
        "Санкт-Петербург",
        "Saint Petersburg",
        ["Петербург", "Питер", "Питера", "Питере", "Питеру", "St. Petersburg", "Petersburg"],
        case_aliases=["СПБ", "SPB"],
    )
    add_city("kazan", "ru", "Казань", "Kazan", ["Казани", "Казанью"], decline_name=False)
    add_city("sochi", "ru", "Сочи", "Sochi", decline_name=False)
    add_city("kaliningrad", "ru", "Калининград", "Kaliningrad")
    add_city(
        "nn",
        "ru",
        "Нижний Новгород",
        "Nizhny Novgorod",
        ["Нижнем Новгороде", "Нижнего Новгорода", "Нижний"],
        decline_name=False,
    )
    add_city("ekb", "ru", "Екатеринбург", "Yekaterinburg")
    add_city("nsk", "ru", "Новосибирск", "Novosibirsk")
    add_city("vladivostok", "ru", "Владивосток", "Vladivostok")
    add_city("irkutsk", "ru", "Иркутск", "Irkutsk")
    add_city("baikal", "ru", "Байкал", "Baikal", ["Байкала", "Байкале", "Байкалу"])
    add_city("murmansk", "ru", "Мурманск", "Murmansk")
    add_city("krasnodar", "ru", "Краснодар", "Krasnodar")
    add_city("yaroslavl", "ru", "Ярославль", "Yaroslavl", ["Ярославля", "Ярославле", "Ярославлю"], decline_name=False)
    add_city("suzdal", "ru", "Суздаль", "Suzdal", ["Суздаля", "Суздале", "Суздалю"], decline_name=False)
    add_city("vladimir", "ru", "Владимир", "Vladimir")
    add_city("pskov", "ru", "Псков", "Pskov")
    add_city("vyborg", "ru", "Выборг", "Vyborg")
    add_city("gelendzhik", "ru", "Геленджик", "Gelendzhik")
    add_city("anapa", "ru", "Анапа", "Anapa", ["Анапы", "Анапе", "Анапу", "Анапой"])
    add_city("kizhi", "ru", "Кижи", "Kizhi", decline_name=False)

    # Ukraine / Belarus / Baltics
    add_city("kyiv", "ua", "Киев", "Kyiv", ["Києва", "Києві", "Київ"])
    add_city("lviv", "ua", "Львов", "Lviv", ["Львова", "Львове", "Львову", "Львів"])
    add_city("odesa", "ua", "Одесса", "Odesa", ["Одессы", "Одессе", "Одессу", "Одессой", "Одеса"])
    add_city("minsk", "by", "Минск", "Minsk")
    add_city("tallinn", "ee", "Таллин", "Tallinn", ["Таллина", "Таллине", "Таллину", "Таллинн", "Таллинна", "Таллинне"])
    add_city("riga", "lv", "Рига", "Riga", ["Риги", "Риге", "Ригу", "Ригой"])
    add_city("vilnius", "lt", "Вильнюс", "Vilnius")

    # Europe
    add_city("warsaw", "pl", "Варшава", "Warsaw")
    add_city("krakow", "pl", "Краков", "Krakow", ["Kraków"])
    add_city("gdansk", "pl", "Гданьск", "Gdansk", ["Гданьска", "Гданьске", "Гданьску"])
    add_city("berlin", "de", "Берлин", "Berlin")
    add_city("munich", "de", "Мюнхен", "Munich")
    add_city("hamburg", "de", "Гамбург", "Hamburg")
    add_city("frankfurt", "de", "Франкфурт", "Frankfurt")
    add_city("cologne", "de", "Кёльн", "Cologne", ["Кельн", "Кёльна", "Кёльне", "Кельна", "Кельне"])
    add_city("dresden", "de", "Дрезден", "Dresden")
    add_city("prague", "cz", "Прага", "Prague")
    add_city("karlovy", "cz", "Карловы Вары", "Karlovy Vary", decline_name=False)
    add_city("bratislava", "sk", "Братислава", "Bratislava", ["Братиславы", "Братиславе", "Братиславу", "Братиславой"])
    add_city("vienna", "at", "Вена", "Vienna")
    add_city("salzburg", "at", "Зальцбург", "Salzburg")
    add_city("zurich", "ch", "Цюрих", "Zurich")
    add_city("geneva", "ch", "Женева", "Geneva", ["Женевы", "Женеве", "Женеву", "Женевой"])
    add_city("paris", "fr", "Париж", "Paris")
    add_city("nice", "fr", "Ницца", "Nice", en_sensitive=True)
    add_city("lyon", "fr", "Лион", "Lyon")
    add_city("marseille", "fr", "Марсель", "Marseille", ["Марселя", "Марселе", "Марселю"], decline_name=False)
    add_city("bordeaux", "fr", "Бордо", "Bordeaux", decline_name=False)
    add_city("strasbourg", "fr", "Страсбург", "Strasbourg")
    add_city(
        "cannes",
        "fr",
        "Канны",
        "Cannes",
        ["Каннах", "Канн"],
        decline_name=False,
    )
    add_city("madrid", "es", "Мадрид", "Madrid")
    add_city("barcelona", "es", "Барселона", "Barcelona", ["Барселоны", "Барселоне", "Барселону", "Барселоной"])
    add_city("seville", "es", "Севилья", "Seville")
    add_city("valencia", "es", "Валенсия", "Valencia")
    add_city("malaga", "es", "Малага", "Malaga", ["Малаги", "Малаге", "Малагу", "Малагой"])
    add_city("bilbao", "es", "Бильбао", "Bilbao", decline_name=False)
    add_city("granada", "es", "Гранада", "Granada", ["Гранады", "Гранаде", "Гранаду", "Гранадой"])
    add_city("rome", "it", "Рим", "Rome", ["Roma"])
    add_city("milan", "it", "Милан", "Milan", ["Milano"])
    add_city("venice", "it", "Венеция", "Venice", ["Venezia"])
    add_city("florence", "it", "Флоренция", "Florence", ["Firenze"])
    add_city("naples", "it", "Неаполь", "Naples", ["Неаполя", "Неаполе", "Неаполю", "Napoli"], decline_name=False)
    add_city("turin", "it", "Турин", "Turin", ["Torino"])
    add_city("bologna", "it", "Болонья", "Bologna")
    add_city("genoa", "it", "Генуя", "Genoa", ["Генуи", "Генуе", "Геную", "Генуей", "Genova"], decline_name=False)
    add_city("amalfi", "it", "Амальфи", "Amalfi", decline_name=False)
    add_city("positano", "it", "Позитано", "Positano", decline_name=False)
    add_city("como", "it", "Комо", "Como", decline_name=False)
    add_city("sicily", "it", "Сицилия", "Sicily")
    add_city("palermo", "it", "Палермо", "Palermo", decline_name=False)
    add_city("sardinia", "it", "Сардиния", "Sardinia")
    add_city("lisbon", "pt", "Лиссабон", "Lisbon", ["Lisboa"])
    add_city("porto", "pt", "Порту", "Porto", decline_name=False)
    add_city("amsterdam", "nl", "Амстердам", "Amsterdam")
    add_city("rotterdam", "nl", "Роттердам", "Rotterdam")
    add_city("brussels", "be", "Брюссель", "Brussels", ["Брюсселя", "Брюсселе", "Брюсселю"], decline_name=False)
    add_city("bruges", "be", "Брюгге", "Bruges", decline_name=False)
    add_city("antwerp", "be", "Антверпен", "Antwerp")
    add_city("luxembourg-city", "lu", "Люксембург", "Luxembourg City")
    add_city("london", "gb", "Лондон", "London")
    add_city("edinburgh", "gb", "Эдинбург", "Edinburgh")
    add_city("manchester", "gb", "Манчестер", "Manchester")
    add_city("liverpool", "gb", "Ливерпуль", "Liverpool", ["Ливерпуля", "Ливерпуле", "Ливерпулю"], decline_name=False)
    add_city("dublin", "ie", "Дублин", "Dublin")
    add_city("reykjavik", "is", "Рейкьявик", "Reykjavik")
    add_city("oslo", "no", "Осло", "Oslo", decline_name=False)
    add_city("bergen", "no", "Берген", "Bergen")
    add_city("stockholm", "se", "Стокгольм", "Stockholm")
    add_city("gothenburg", "se", "Гётеборг", "Gothenburg", ["Гетеборг", "Гётеборга", "Гётеборге"])
    add_city("copenhagen", "dk", "Копенгаген", "Copenhagen")
    add_city("helsinki", "fi", "Хельсинки", "Helsinki", decline_name=False)
    add_city("athens", "gr", "Афины", "Athens", ["Афинах", "Афин"], decline_name=False)
    add_city("santorini", "gr", "Санторини", "Santorini", decline_name=False)
    add_city("crete", "gr", "Крит", "Crete")
    add_city("rhodes", "gr", "Родос", "Rhodes")
    add_city("mykonos", "gr", "Миконос", "Mykonos")
    add_city("thessaloniki", "gr", "Салоники", "Thessaloniki", decline_name=False)
    add_city("zagreb", "hr", "Загреб", "Zagreb")
    add_city("split", "hr", "Сплит", "Split", en_sensitive=True)
    add_city("dubrovnik", "hr", "Дубровник", "Dubrovnik")
    add_city("budva", "me", "Будва", "Budva", ["Будвы", "Будве", "Будву", "Будвой"])
    add_city("kotor", "me", "Котор", "Kotor")
    add_city("belgrade", "rs", "Белград", "Belgrade")
    add_city("ljubljana", "si", "Любляна", "Ljubljana", ["Любляны", "Любляне", "Любляну", "Любляной"])
    add_city("sarajevo", "ba", "Сараево", "Sarajevo", decline_name=False)
    add_city("tirana", "al", "Тирана", "Tirana", ["Тираны", "Тиране", "Тирану", "Тираной"])
    add_city("sofia", "bg", "София", "Sofia")
    add_city("bucharest", "ro", "Бухарест", "Bucharest")
    add_city("budapest", "hu", "Будапешт", "Budapest")
    add_city("chisinau", "md", "Кишинёв", "Chisinau", ["Кишинев", "Кишинёва", "Кишинёве", "Кишинева", "Кишиневе"])
    add_city("nicosia", "cy", "Никосия", "Nicosia")
    add_city("limassol", "cy", "Лимассол", "Limassol")
    add_city("valletta", "mt", "Валлетта", "Valletta", ["Валлетты", "Валлетте", "Валлетту", "Валлеттой"])
    add_city("monaco", "mc", "Монако", "Monaco", decline_name=False)
    add_city("andorra", "ad", "Андорра-ла-Велья", "Andorra la Vella", decline_name=False)

    # Turkey
    add_city("istanbul", "tr", "Стамбул", "Istanbul", ["İstanbul", "İstanbula"])
    add_city("ankara", "tr", "Анкара", "Ankara")
    add_city("izmir", "tr", "Измир", "Izmir", ["İzmir"])
    add_city("antalya", "tr", "Анталья", "Antalya")
    add_city("cappadocia", "tr", "Каппадокия", "Cappadocia", ["Kapadokya"])
    add_city("goreme", "tr", "Гёреме", "Goreme", ["Гереме", "Göreme"], decline_name=False)
    add_city("bodrum", "tr", "Бодрум", "Bodrum")
    add_city("fethiye", "tr", "Фетхие", "Fethiye", decline_name=False)
    add_city("alanya", "tr", "Аланья", "Alanya")
    add_city("marmaris", "tr", "Мармарис", "Marmaris")
    add_city("trabzon", "tr", "Трабзон", "Trabzon")
    add_city("bursa", "tr", "Бурса", "Bursa", ["Бурсы", "Бурсе", "Бурсу", "Бурсой"])
    add_city("eskisehir", "tr", "Эскишехир", "Eskisehir", ["Eskişehir"])
    add_city("kusadasi", "tr", "Кушадасы", "Kusadasi", ["Kuşadası"], decline_name=False)
    add_city("cesme", "tr", "Чешме", "Cesme", ["Çeşme"], decline_name=False)
    add_city("pamukkale", "tr", "Памуккале", "Pamukkale", decline_name=False)
    add_city("ephesus", "tr", "Эфес", "Ephesus", ["Efes"])
    add_city("side", "tr", "Сиде", "Side", en_sensitive=True, decline_name=False)
    add_city("belek", "tr", "Белек", "Belek")
    add_city("kemer", "tr", "Кемер", "Kemer")
    add_city("oludeniz", "tr", "Улудениз", "Oludeniz", ["Ölüdeniz"])

    # Caucasus / Central Asia
    add_city("tbilisi", "ge", "Тбилиси", "Tbilisi", decline_name=False)
    add_city("batumi", "ge", "Батуми", "Batumi", decline_name=False)
    add_city("kutaisi", "ge", "Кутаиси", "Kutaisi", decline_name=False)
    add_city("yerevan", "am", "Ереван", "Yerevan")
    add_city("baku", "az", "Баку", "Baku", decline_name=False)
    add_city("almaty", "kz", "Алматы", "Almaty", decline_name=False)
    add_city("astana", "kz", "Астана", "Astana", ["Нур-Султан", "Nur-Sultan", "Астаны", "Астане", "Астану", "Астаной"])
    add_city("tashkent", "uz", "Ташкент", "Tashkent")
    add_city("samarkand", "uz", "Самарканд", "Samarkand")
    add_city("bukhara", "uz", "Бухара", "Bukhara", ["Бухары", "Бухаре", "Бухару", "Бухарой"])
    add_city("bishkek", "kg", "Бишкек", "Bishkek")

    # East / SE Asia
    add_city("beijing", "cn", "Пекин", "Beijing")
    add_city("shanghai", "cn", "Шанхай", "Shanghai")
    add_city("guangzhou", "cn", "Гуанчжоу", "Guangzhou", decline_name=False)
    add_city("shenzhen", "cn", "Шэньчжэнь", "Shenzhen", ["Шэньчжэня", "Шэньчжэне", "Шэньчжэню"], decline_name=False)
    add_city("chengdu", "cn", "Чэнду", "Chengdu", decline_name=False)
    add_city("xian", "cn", "Сиань", "Xi'an", ["Сианя", "Сиане", "Сианю", "Xian"], decline_name=False)
    add_city("guilin", "cn", "Гуйлинь", "Guilin", ["Гуйлиня", "Гуйлине", "Гуйлиню"], decline_name=False)
    add_city("hongkong", "cn", "Гонконг", "Hong Kong")
    add_city("macau", "cn", "Макао", "Macau", ["Макау", "Macao"], decline_name=False)
    add_city("taipei", "tw", "Тайбэй", "Taipei", ["Тайбэя", "Тайбэе", "Тайпея", "Тайпее"])
    add_city("tokyo", "jp", "Токио", "Tokyo", decline_name=False)
    add_city("kyoto", "jp", "Киото", "Kyoto", decline_name=False)
    add_city("osaka", "jp", "Осака", "Osaka")
    add_city("nara", "jp", "Нара", "Nara")
    add_city("sapporo", "jp", "Саппоро", "Sapporo", decline_name=False)
    add_city("yokohama", "jp", "Йокогама", "Yokohama", ["Йокогамы", "Йокогаме", "Йокогаму", "Йокогамой"])
    add_city("seoul", "kr", "Сеул", "Seoul")
    add_city("busan", "kr", "Пусан", "Busan")
    add_city("bangkok", "th", "Бангкок", "Bangkok")
    add_city("phuket", "th", "Пхукет", "Phuket")
    add_city("chiangmai", "th", "Чиангмай", "Chiang Mai")
    add_city("pattaya", "th", "Паттайя", "Pattaya")
    add_city("samui", "th", "Самуи", "Samui", ["Koh Samui", "Ко Самуи"], decline_name=False)
    add_city("krabi", "th", "Краби", "Krabi", decline_name=False)
    add_city("hanoi", "vn", "Ханой", "Hanoi")
    add_city("hochiminh", "vn", "Хошимин", "Ho Chi Minh City", ["Сайгон", "Сайгона", "Сайгоне", "Saigon"])
    add_city("danang", "vn", "Дананг", "Da Nang")
    add_city("hoian", "vn", "Хойан", "Hoi An")
    add_city("nhatrang", "vn", "Нячанг", "Nha Trang")
    add_city("singapore", "sg", "Сингапур", "Singapore")
    add_city("kualalumpur", "my", "Куала-Лумпур", "Kuala Lumpur")
    add_city("penang", "my", "Пенанг", "Penang")
    add_city("bali", "id", "Бали", "Bali", decline_name=False)
    add_city("jakarta", "id", "Джакарта", "Jakarta", ["Джакарты", "Джакарте", "Джакарту", "Джакартой"])
    add_city("ubud", "id", "Убуд", "Ubud")
    add_city("seminyak", "id", "Семиньяк", "Seminyak")
    add_city("manila", "ph", "Манила", "Manila", ["Манилы", "Маниле", "Манилу", "Манилой"])
    add_city("cebu", "ph", "Себу", "Cebu", decline_name=False)
    add_city("phnompenh", "kh", "Пномпень", "Phnom Penh", ["Пномпеня", "Пномпене"], decline_name=False)
    add_city("siemreap", "kh", "Сиемреап", "Siem Reap")

    # South Asia / Middle East / Africa
    add_city("delhi", "in", "Дели", "Delhi", decline_name=False)
    add_city("mumbai", "in", "Мумбаи", "Mumbai", decline_name=False)
    add_city("goa", "in", "Гоа", "Goa", decline_name=False)
    add_city("jaipur", "in", "Джайпур", "Jaipur")
    add_city("agra", "in", "Агра", "Agra", ["Агры", "Агре", "Агру", "Агрой"])
    add_city("colombo", "lk", "Коломбо", "Colombo", decline_name=False)
    add_city("kathmandu", "np", "Катманду", "Kathmandu", decline_name=False)
    add_city("male", "mv", "Мале", "Male", decline_name=False)
    add_city("dubai", "ae", "Дубай", "Dubai")
    add_city("abudhabi", "ae", "Абу-Даби", "Abu Dhabi", decline_name=False)
    add_city("sharjah", "ae", "Шарджа", "Sharjah", ["Шарджи", "Шардже", "Шарджу", "Шарджой"])
    add_city("doha", "qa", "Доха", "Doha", ["Дохи", "Дохе", "Доху", "Дохой"])
    add_city("riyadh", "sa", "Эр-Рияд", "Riyadh")
    add_city("jeddah", "sa", "Джидда", "Jeddah", ["Джидды", "Джидде", "Джидду", "Джиддой"])
    add_city("muscat", "om", "Мускат", "Muscat")
    add_city("telaviv", "il", "Тель-Авив", "Tel Aviv")
    add_city("jerusalem", "il", "Иерусалим", "Jerusalem")
    add_city("amman", "jo", "Амман", "Amman")
    add_city("cairo", "eg", "Каир", "Cairo")
    add_city("hurghada", "eg", "Хургада", "Hurghada", ["Хургады", "Хургаде", "Хургаду", "Хургадой"])
    add_city("sharm", "eg", "Шарм-эш-Шейх", "Sharm el-Sheikh", ["Шарм-эль-Шейх"])
    add_city("marrakesh", "ma", "Марракеш", "Marrakesh", ["Марракеша", "Марракеше", "Marrakech"])
    add_city("casablanca", "ma", "Касабланка", "Casablanca", ["Касабланки", "Касабланке", "Касабланку", "Касабланкой"])
    add_city("tunis", "tn", "Тунис", "Tunis")
    add_city("cape-town", "za", "Кейптаун", "Cape Town")
    add_city("nairobi", "ke", "Найроби", "Nairobi", decline_name=False)
    add_city("zanzibar", "tz", "Занзибар", "Zanzibar")
    add_city("mauritius-city", "mu", "Маврикий", "Mauritius")

    # Americas / Oceania
    add_city(
        "nyc",
        "us",
        "Нью-Йорк",
        "New York",
        ["New York City"],
        case_aliases=["NYC"],
    )
    add_city("la", "us", "Лос-Анджелес", "Los Angeles")
    add_city("sf", "us", "Сан-Франциско", "San Francisco", decline_name=False)
    add_city("chicago", "us", "Чикаго", "Chicago", decline_name=False)
    add_city("miami", "us", "Майами", "Miami", decline_name=False)
    add_city("vegas", "us", "Лас-Вегас", "Las Vegas")
    add_city("boston", "us", "Бостон", "Boston")
    add_city("washington", "us", "Вашингтон", "Washington")
    add_city("seattle", "us", "Сиэтл", "Seattle")
    add_city("toronto", "ca", "Торонто", "Toronto", decline_name=False)
    add_city("vancouver", "ca", "Ванкувер", "Vancouver")
    add_city("montreal", "ca", "Монреаль", "Montreal", ["Монреаля", "Монреале", "Монреалю"], decline_name=False)
    add_city("mexicocity", "mx", "Мехико", "Mexico City", decline_name=False)
    add_city("cancun", "mx", "Канкун", "Cancun")
    add_city("buenosaires", "ar", "Буэнос-Айрес", "Buenos Aires")
    add_city("rio", "br", "Рио-де-Жанейро", "Rio de Janeiro", ["Рио", "Rio"], decline_name=False)
    add_city("saopaulo", "br", "Сан-Паулу", "Sao Paulo", ["São Paulo"], decline_name=False)
    add_city("lima", "pe", "Лима", "Lima", ["Лимы", "Лиме", "Лиму", "Лимой"])
    add_city("santiago", "cl", "Сантьяго", "Santiago", decline_name=False)
    add_city("havana", "cu", "Гавана", "Havana", ["Гаваны", "Гаване", "Гавану", "Гаваной"])
    add_city("sydney", "au", "Сидней", "Sydney")
    add_city("melbourne", "au", "Мельбурн", "Melbourne")
    add_city("auckland", "nz", "Окленд", "Auckland")


def main() -> None:
    build()
    country_ids = {c["id"] for c in countries}
    errors: list[str] = []
    for city in cities:
        if city["country"] not in country_ids:
            errors.append(f"city {city['id']} has unknown country {city['country']}")
    # Warn on duplicate folded aliases inside the same kind.
    def audit(rows: list[dict], kind: str) -> None:
        seen: dict[str, str] = {}
        for row in rows:
            forms = [row["ru"], row["en"]] + row["aliases"] + row["caseAliases"]
            if row.get("enSensitive"):
                pass
            for form in forms:
                key = form.casefold()
                if key in seen and seen[key] != row["id"]:
                    errors.append(f"duplicate {kind} alias {form!r}: {seen[key]} and {row['id']}")
                else:
                    seen[key] = row["id"]

    audit(countries, "country")
    audit(cities, "city")
    if errors:
        print("GEO DATA PROBLEMS:")
        for err in errors:
            print(" -", err)
        raise SystemExit(1)
    payload = {"countries": countries, "cities": cities}
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {OUT} countries={len(countries)} cities={len(cities)}")
    # Spot-check a few declensions for the log.
    samples = ["Стамбул", "Турция", "Франция", "Париж", "Ницца", "Москва", "Санкт-Петербург", "Пекин", "Анталья"]
    for name in samples:
        print(f"  {name}: {', '.join(decline(name))}")


if __name__ == "__main__":
    main()
