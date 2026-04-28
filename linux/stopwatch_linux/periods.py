from enum import Enum


class Period(Enum):
    MORNING = "morning"
    AFTERNOON = "afternoon"
    NIGHT = "night"

    @property
    def label(self) -> str:
        return {
            Period.MORNING: "Morning",
            Period.AFTERNOON: "Afternoon",
            Period.NIGHT: "Night",
        }[self]

    def contains_hour(self, hour: int) -> bool:
        if self is Period.MORNING:
            return 5 <= hour <= 11
        if self is Period.AFTERNOON:
            return 12 <= hour <= 17
        return hour >= 18 or hour < 5

    @classmethod
    def ordered(cls):
        return [cls.MORNING, cls.AFTERNOON, cls.NIGHT]
