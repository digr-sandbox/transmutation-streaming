import { Injectable, Logger } from '@nestjs/common';

@Injectable()
export class TokenSqueezer {
    private readonly logger = new Logger(TokenSqueezer.name);

    async squeeze(tokens: string[]): Promise<number> {
        this.logger.debug(`Squeezing ${tokens.length} tokens`);
        return tokens.length * 0.5;
    }
}