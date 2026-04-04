import logging
from typing import List

class SemanticEngine:
    def __init__(self, model_name: str):
        self.logger = logging.getLogger(__name__)
        self.model = model_name

    def predict(self, inputs: List[float]) -> bool:
        self.logger.info(f"Python predicting with {self.model}")
        return sum(inputs) > 0.5