/*
 * Copyright 2002-present the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package org.springframework.core;

/**
 * {@code Ordered} is an interface that can be implemented by objects that
 * should be <em>orderable</em>, for example in a {@code Collection}.
 *
 * <p>The actual {@link #getOrder() order} can be interpreted as prioritization,
 * with the first object (with the lowest order value) having the highest
 * priority.
 *
 * <p>Note that 
