"""
Версия — это просто СТРОКА, которую разработчик придумывает и полностью контролирует сам (любой
текст, хоть "HJDF3123Hj0"), плюс ОДНО число в конце после запятой — номер пуша (push_count),
который видит и меняет только сам демон.

Раньше вся версия целиком обязана была совпадать со строгим форматом
(Stable,StablePatch.Beta,BetaPush...) — и любое отклонение (например тег, поправленный руками
не по формату) роняло программу с ValueError. Теперь демон вообще не разбирает и не проверяет
содержимое префикса — это дело разработчика, программа умеет только отделить последнее число
(после последней запятой) и увеличивать его на пуше. Если такого числа нет — просто считаем,
что пушей ещё не было (push_count = 0), и НЕ падаем.
"""

from typing import Tuple


def split_prefix_and_push(tag: str) -> Tuple[str, int]:
    """'2,1.5,3.7,4,9' -> ('2,1.5,3.7,4', 9). Если после последней запятой не целое число (или
    запятой в теге вообще нет) — весь тег считается префиксом, а push_count = 0."""
    tag = tag.strip()
    if "," in tag:
        prefix, last = tag.rsplit(",", 1)
        last = last.strip()
        if last.lstrip("-").isdigit():
            return prefix, int(last)
    return tag, 0


def next_tag(tag: str) -> str:
    """Тег для следующего автоматического пуша — тот же префикс, push_count + 1."""
    prefix, push_count = split_prefix_and_push(tag)
    return build_tag(prefix, push_count + 1)


def build_tag(prefix: str, push_count: int = 0) -> str:
    return f"{prefix},{push_count}"


if __name__ == "__main__":
    assert split_prefix_and_push("2,1.5,3.7,4,9") == ("2,1.5,3.7,4", 9)
    assert next_tag("2,1.5,3.7,4,9") == "2,1.5,3.7,4,10"
    assert build_tag("2,1.5,3.7,4", 9) == "2,1.5,3.7,4,9"

    # Тег, поправленный вручную не по формату, — раньше падало, теперь просто push_count = 0
    assert split_prefix_and_push("HJDF3123Hj0") == ("HJDF3123Hj0", 0)
    assert next_tag("HJDF3123Hj0") == "HJDF3123Hj0,1"

    # Старый тег с буквой статуса (до отказа от статусов) — тоже просто часть префикса, не падает
    prefix, push = split_prefix_and_push("G0,0.0,0.7,0,2")
    assert (prefix, push) == ("G0,0.0,0.7,0", 2)

    print("version.py: самопроверка пройдена")
