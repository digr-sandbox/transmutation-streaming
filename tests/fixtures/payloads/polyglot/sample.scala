package transmutation.fp

trait Transformable[T] {
    def transform(item: T): T
}

object GlobalProcessor extends App {
    def run[T](input: List[T])(implicit t: Transformable[T]): List[T] = {
        input.map(t.transform)
    }
}